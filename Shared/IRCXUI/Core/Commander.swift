import EmberKit
import Foundation

/** What the input line's commands do, whichever theme's input line they were typed in. */
@MainActor
enum Commander {
  static func run(_ command: InputCommand, app: AppModel, session: InstanceSession, room: RoomModel) {
    switch command {
    case let .say(text): room.send(text)
    case let .me(action): room.send(action, action: true)
    case let .join(name):
      Task { do { try await session.join(name) } catch { room.note(error.localizedDescription, kind: .error) } }
    case let .msg(nick, text):
      Task {
        do {
          let buffer = try await session.query(nick)
          if let text, let buffer {
            // Its socket opens as the buffer comes on screen; send once it has.
            for _ in 0..<50 where !buffer.isOpen { try? await Task.sleep(for: .milliseconds(100)) }
            buffer.send(text)
          }
        } catch {
          room.note(error.localizedDescription, kind: .error)
        }
      }
    case let .query(nicks):
      Task { do { _ = try await session.query(nicks) } catch { room.note(error.localizedDescription, kind: .error) } }
    case .part:
      // Closes the window here only: Ember has no leaving an open room. With nowhere to go back to, another window.
      if app.canGoBack {
        app.goBack()
      } else if let other = session.windows.first(where: { $0.id != room.id }) {
        session.open(room: other.id)
      } else {
        room.note("No other window to go to", kind: .error)
      }
    case .leave:
      guard room.room.kind == .closed else { return room.note("Everyone is in an open room, so nobody can leave it", kind: .error) }
      session.confirmation = .leave(room.id)
    case .back: app.goBack()
    case .forward: app.goForward()
    case .home: session.goHome()
    case let .star(name, on):
      guard let target = target(name, session: session, room: room) else { return }
      guard !target.room.isDirect else { return room.note("A DM can't be starred", kind: .error) }
      if session.isStarred(target.id) != on { session.toggleFavorite(target.id) }
    case let .move(move):
      guard session.isStarred(room.id) else { return room.note("Only a starred room moves among the starred", kind: .error) }
      session.moveStar(room.id, move)
    case let .notify(level, name):
      guard let item = target(name, session: session, room: room) else { return }
      guard let level else {
        guard let name else { return room.note(item.involvement.sentence) }
        return room.note("#\(name): \(item.involvement.sentence)")
      }
      guard Involvement.levels(in: item.room).contains(level) else { return room.note("A DM's notifications are everything or off", kind: .error) }
      session.setInvolvement(level, for: item.id)
    case let .push(action):
      runPush(action, session: session, room: room)
    case let .hide(name, hidden):
      guard let target = target(name, session: session, room: room) else { return }
      if hidden {
        guard !target.room.isDirect else { return room.note("A DM's notifications are everything or off", kind: .error) }
        session.setInvolvement(.invisible, for: target.id)
      } else {
        session.setInvolvement(Involvement.starting(in: target.room), for: target.id)
      }
    case let .newRoom(name, closed, nicks):
      guard session.canCreateRooms else { return room.note("Only administrators can create rooms", kind: .error) }
      Task {
        do {
          let ids = try nicks.map { nick in
            guard let person = session.person(named: nick) else { throw EmberError.refused(404, "No such nick: \(nick)") }
            return person.id
          }
          let made = try await session.createRoom(name: name, icon: nil, closed: closed, memberIds: ids)
          session.buffer(made.id)?.note("Created \(closed ? "&" : "#")\(made.name ?? name)")
        } catch {
          room.note(error.localizedDescription, kind: .error)
        }
      }
    case let .rename(name):
      change(room, session: session) { _ in RoomChanges(name: name) }
    case .room:
      Task { await printSettings(of: room, session: session) }
    case .makeOpen:
      change(room, session: session) { _ in RoomChanges(kind: .open) }
    case let .makePrivate(nicks):
      change(room, session: session) { settings in
        var members = settings.people.filter(\.member).map(\.id)
        for nick in nicks {
          guard let person = session.person(named: nick) else { throw EmberError.refused(404, "No such nick: \(nick)") }
          if !members.contains(person.id) { members.append(person.id) }
        }
        if let me = session.me?.id, !members.contains(me) { members.insert(me, at: 0) }
        return RoomChanges(kind: .closed, memberIds: members)
      }
    case let .invite(nick):
      guard let nick else {
        Task { await printJoinLink(session: session, room: room) }
        return
      }
      guard room.room.kind == .closed else { return room.note("Everyone is in an open room already", kind: .error) }
      change(room, session: session) { settings in
        guard let person = session.person(named: nick) else { throw EmberError.refused(404, "No such nick: \(nick)") }
        let members = settings.people.filter(\.member).map(\.id)
        return RoomChanges(kind: .closed, memberIds: members.contains(person.id) ? members : members + [person.id])
      }
    case let .kick(nick):
      guard room.room.kind == .closed else { return room.note("Everyone is in an open room, so nobody can leave it", kind: .error) }
      change(room, session: session) { settings in
        guard let person = session.person(named: nick) else { throw EmberError.refused(404, "No such nick: \(nick)") }
        return RoomChanges(kind: .closed, memberIds: settings.people.filter { $0.member && $0.id != person.id }.map(\.id))
      }
    case .deleteRoom:
      session.confirmation = .delete(room.id)
    case .dismiss:
      Task {
        do { try await session.dismissInvitation() } catch { room.note(error.localizedDescription, kind: .error) }
      }
    case let .search(text):
      let (search, sort) = session.typedSearch(text)
      guard search.isSearchable else { return room.note(NavigationText.searchHint, kind: .error) }
      session.runSearch(search, sort: sort ?? .newest)
    case .more:
      guard session.search.next != nil else { return room.note("No more results", kind: .error) }
      session.show(.search(session.search.search, session.search.sort))
      session.moreResults()
    case let .searches(clear):
      if clear {
        session.confirmation = .clearSearches
      } else {
        session.show(.search(session.search.search, session.search.sort))
        session.loadRecentSearches()
      }
    case let .goto(n):
      guard session.search.matches.indices.contains(n - 1) else { return room.note("No result \(n)", kind: .error) }
      session.open(session.search.matches[n - 1])
    case .activity:
      session.toggleActivity()
      room.note(session.showingActivity ? "Activity: only unread conversations" : "Activity off: every conversation")
    case let .ban(nick, banned):
      guard session.me?.administrator == true else { return room.note("Only administrators can ban people", kind: .error) }
      guard let person = session.people.values.first(where: { $0.name.caseInsensitiveCompare(nick) == .orderedSame || $0.username == nick }) else {
        return room.note("\(nick): No such nick", kind: .error)
      }
      session.confirmation = .ban(person.id, banned)
    case .names:
      let names = room.timeline.present.map(\.name).sorted().joined(separator: " ")
      room.note("[Users \(room.room.isDirect ? room.title : "#" + room.title)] \(names)")
    case let .whois(nick):
      guard let person = session.people.values.first(where: { $0.name.caseInsensitiveCompare(nick) == .orderedSame || $0.username == nick })
        ?? session.person(named: nick)
      else { return room.note("\(nick): No such nick", kind: .error) }
      Task {
        do {
          room.print(PersonFacts.lines(try await session.api.person(person.id), session: session))
        } catch {
          room.note(error.localizedDescription, kind: .error)
        }
      }
    case let .server(address):
      if let link = EmberLink.parse(address) {
        app.follow(link)
      } else {
        room.note("Not an address: \(address)", kind: .error)
      }
    case .help:
      room.note(InputCommand.helpText)
    case .shortcuts:
      room.request = .shortcuts
    case let .edit(n, text):
      guard let message = room.message(numbered: n, mine: true) else { return room.note("No message of yours to edit", kind: .error) }
      guard !MessageAction.editsFixed(message) else { return room.note("That message's text can't be edited", kind: .error) }
      if let text { room.edit(message, to: text) } else { room.request = .editLine(message, inThread: false) }
    case let .quote(n):
      guard let message = room.message(numbered: n), message.attachment == nil, message.huddle == nil else { return room.note("No message to quote", kind: .error) }
      room.quote(message, into: room.composer())
    case let .delete(n):
      guard let message = room.message(numbered: n, mine: session.me?.administrator != true) else { return room.note("No message to delete", kind: .error) }
      room.request = .delete(message)
    case let .copy(n):
      guard let message = room.message(numbered: n) else { return room.note("No message to copy", kind: .error) }
      Pasteboard.copy(message.plainText)
      room.print(["Copied"])
    case let .link(n):
      guard let message = room.message(numbered: n) else { return room.note("No message to link to", kind: .error) }
      Pasteboard.copy(room.permalink(message))
      room.print(["Copied \(room.permalink(message))"])
    case let .react(content, n):
      guard let message = room.message(numbered: n) else { return room.note("No message to react to", kind: .error) }
      room.react(content, to: message)
    case let .thread(n):
      guard let message = room.message(numbered: n) else { return room.note("No message to open", kind: .error) }
      room.openThread(message.parentId ?? message.id)
    case .upload:
      room.request = .upload
    case let .snippet(title):
      room.request = .snippet(title)
    case let .report(n):
      guard let message = room.message(numbered: n), message.creator.id != session.me?.id, message.huddle == nil else { return room.note("No message to report", kind: .error) }
      room.request = .report(message)
    case let .reportPerson(nick):
      guard let person = session.person(named: nick) ?? session.people.values.first(where: { $0.username == nick }) else {
        return room.note("\(nick): No such nick", kind: .error)
      }
      guard person.id != session.me?.id else { return room.note("You can't report yourself", kind: .error) }
      Task {
        do {
          session.reportingPerson = try await session.api.person(person.id).person
        } catch {
          room.note(error.localizedDescription, kind: .error)
        }
      }
    case let .ignore(nick, blocked):
      guard let person = session.people.values.first(where: { $0.name.caseInsensitiveCompare(nick) == .orderedSame || $0.username == nick }) else {
        return room.note("\(nick): No such nick", kind: .error)
      }
      room.setBlocked(blocked, person.id)
    case .end:
      room.jumpToNewest()
    case .ignored, .profile, .profileElsewhere, .setProfile, .passwd, .avatar, .apps, .ai, .sounds, .appearance, .quit, .deleteAccount:
      PeopleCommands.run(command, session: session, room: room)
    case let .admin(command):
      AdminCommander.run(command, app: app, session: session, room: room)
    case let .huddle(action):
      HuddleCommander.run(action, app: app, session: session, room: room)
    case let .unknown(reason):
      room.note(reason, kind: .error)
    }
  }

  /** The room a command names, or the open one. */
  private static func target(_ name: String?, session: InstanceSession, room: RoomModel) -> SidebarRoom? {
    guard let name else { return session.rooms.first { $0.id == room.id } }
    guard let found = session.room(named: name) else {
      room.note("#\(name): No such channel", kind: .error)
      return nil
    }
    return found
  }

  /** Changes the open room's settings from what they are now, as its settings page saves them. */
  private static func change(_ room: RoomModel, session: InstanceSession, _ changes: @escaping @MainActor (RoomSettings) throws -> RoomChanges) {
    guard !room.room.isDirect else { return room.note("A DM has no settings to change", kind: .error) }
    Task {
      do {
        let settings = try await session.api.roomSettings(room.id)
        guard settings.canAdminister else { throw EmberError.refused(403, "Only administrators and the room's creator can change it") }
        try await session.changeRoom(room.id, try changes(settings))
        room.note("Saved")
      } catch {
        room.note(error.localizedDescription, kind: .error)
      }
    }
  }

  /** `/room`: the room's settings, as its settings page shows them. */
  private static func printSettings(of room: RoomModel, session: InstanceSession) async {
    if room.room.isDirect {
      let members = RoomList.membersShown(room.room, me: session.me?.id).map { session.people[$0.id]?.name ?? $0.name }
      room.print(["DM with \(RoomList.toSentence(members))", "/deleteroom deletes it and all messages in it"])
      return
    }
    do {
      let settings = try await session.api.roomSettings(room.id)
      let members = settings.people.filter(\.member).map(\.name)
      var lines = [
        "\(settings.room.kind == .closed ? "&" : "#")\(settings.room.name ?? room.title) [\(settings.room.kind == .closed ? "private" : "everyone")]",
        settings.room.kind == .closed ? "Members (\(members.count)): \(members.joined(separator: ", "))" : "Everyone is in it",
      ]
      if let item = session.rooms.first(where: { $0.id == room.id }) { lines.append(item.involvement.sentence) }
      if session.account?.huddles == true { lines.append(settings.room.allowsHuddles ? NavigationText.canStartHuddles : NavigationText.cannotStartHuddles) }
      lines.append(
        settings.canAdminister
          ? "/rename name · /open · /private [nick...] · /invite nick · /kick nick · /deleteroom"
          : settings.room.kind == .closed ? "/leave takes you out of it" : "Only administrators and the room's creator can change it")
      room.print(lines)
    } catch {
      room.note(error.localizedDescription, kind: .error)
    }
  }

  /** `/invite`: the join link, for administrators. */
  private static func printJoinLink(session: InstanceSession, room: RoomModel) async {
    if let code = session.invitation?.joinCode {
      return room.print(["Join link: \(session.joinLink(code))", NavigationText.joinShareText])
    }
    do {
      guard let code = try await session.api.workspaceSettings().joinCode, session.account?.joinsWithLink == true else {
        return room.note("This workspace has no join link", kind: .error)
      }
      room.print(["Join link: \(session.joinLink(code))", NavigationText.joinShareText])
    } catch {
      room.note(error.localizedDescription, kind: .error)
    }
  }

  /** Steps through the selected instance's windows by `by`, as ⌥↑ and ⌥↓ do. */
  static func step(_ by: Int, in session: InstanceSession) {
    let windows = session.windows.map(\.id)
    guard !windows.isEmpty else { return }
    let current = session.selectedRoomID.flatMap { windows.firstIndex(of: $0) } ?? -by
    session.selectedRoomID = windows[(current + by + windows.count) % windows.count]
  }
}

/** What `/whois` prints of someone, as their page shows them (web `PersonPage`). */
@MainActor
enum PersonFacts {
  static func lines(_ answer: PersonAnswer, session: InstanceSession) -> [String] {
    let person = answer.person
    var name = person.name
    if let username = person.username { name += " @\(username)" }
    var lines = ["\(name) [\(person.role.rawValue), \(person.status.rawValue)]"]
    if let email = person.emailAddress { lines.append("email: \(email)") }
    if let bio = person.bio, !bio.isEmpty { lines.append(bio) }
    if let agent = answer.agent {
      lines.append(agent.description)
      lines.append(agent.about(me: session.me?.id, setUpByName: session.people[agent.setUpBy.id]?.name ?? agent.setUpBy.name))
    }
    switch person.status {
    case .deactivated: lines.append(NavigationText.noLongerHere(person.name))
    case .suspended: lines.append(session.me?.administrator == true ? NavigationText.lapsed(person.name) : NavigationText.noLongerHere(person.name))
    case .banned: lines.append("Banned")
    case .active: break
    }
    if person.role != .bot, person.agent != true, let active = session.presence(of: person.id) { lines.append(active ? "active" : "away") }
    if session.isBlocked(person.id) { lines.append("Blocked: /unblock \(person.name)") }
    if let transfer = answer.transferId {
      lines.append("Sign-in link: \(session.instance.origin)\(Pages.transferLink(transfer))")
    }
    return lines
  }
}

extension Commander {
  /** `/push`: this device's notifications from this server, and the devices and browsers notified. */
  static func runPush(_ action: InputCommand.PushAction, session: InstanceSession, room: RoomModel) {
    let push = PushCenter.shared
    Task {
      do {
        switch action {
        case .status:
          let state = push.state(of: session)
          room.note("Notifications: \(PushText.state(state)). \(PushText.detail(state))")
        case .on:
          await push.turnOn(session)
          let state = push.state(of: session)
          if state == .on || state == .turningOn {
            room.note("Notifications: \(PushText.state(state))")
          } else {
            room.note("\(PushText.state(state)). \(PushText.detail(state))", kind: .error)
          }
        case .off:
          try await push.turnOff(session)
          room.note("Notifications: Off")
        case .list:
          async let devices = session.api.deviceTokens()
          async let browsers = session.api.pushSubscriptions()
          let (deviceList, browserList) = try await (devices, browsers)
          if deviceList.isEmpty && browserList.isEmpty { return room.note("No devices or browsers are notified") }
          for device in deviceList {
            let mine = device.token == push.token ? " (this device)" : ""
            room.note("\(InputCommand.PushTarget.device(device.id)) \(Push.label(device))\(mine) · \(device.origin)")
          }
          for browser in browserList {
            room.note("\(InputCommand.PushTarget.browser(browser.id)) \(Push.label(browser))")
          }
        case let .test(target):
          if let target {
            try await push.test(target, on: session)
          } else {
            guard let device = try await push.thisDevice(on: session) else { return room.note("This device isn't notified: /push on", kind: .error) }
            try await push.test(.device(device.id), on: session)
          }
          room.note(PushText.testSent)
        case let .delete(target):
          try await push.delete(target, on: session)
          room.note("Deleted \(target)")
        }
      } catch {
        logger.error("/push on \(session.instance.host, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        room.note(error.localizedDescription, kind: .error)
      }
    }
  }
}
