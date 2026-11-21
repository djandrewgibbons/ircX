import AppCoreUI
import EmberKit
import SwiftUI

/**
 * The search box (web `SearchBox`): words, the filter chips, completions for a modifier being typed,
 * Show results for, and the recent searches.
 */
struct SearchBoxSheet: View {
  let session: InstanceSession
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var text = ""
  @State private var filters = Search(q: "")
  @State private var showingMore = false
  @State private var confirmingClear = false

  private var room: RoomID? { session.searchBoxRoom }

  private var typed: Search {
    var (search, _) = session.typedSearch(text)
    if search.in == nil { search.in = filters.in }
    if search.from == nil { search.from = filters.from }
    for flag in Search.Flag.allCases where filters.has(flag) { search.set(flag, true) }
    return search
  }

  private var completions: [(label: String, insert: String)] {
    guard let modifier = Searches.modifierTyped(text) else { return [] }
    let sought = PeopleList.folded(modifier.value)
    switch modifier.key {
    case "in":
      let rooms = (session.orderedRooms + session.orderedDirects).filter { PeopleList.folded(session.title(of: $0.room)).contains(sought) }
      return rooms.prefix(8).map { (label: session.title(of: $0.room), insert: "in:\($0.room.name ?? $0.id)") }
    case "from":
      guard let me = session.me else { return [] }
      var people: [(label: String, insert: String)] = [("Me (\(me.name))", "from:me")]
      let others = PeopleList.byName(session.people.values.filter { $0.status != .banned && $0.id != me.id && PeopleList.folded($0.name).contains(sought) })
      people += others.prefix(7).map { (label: $0.name, insert: "from:\($0.username ?? $0.name)") }
      return people
    default:
      return Search.Flag.allCases.filter { $0.key == modifier.key && $0.value.hasPrefix(modifier.value.lowercased()) }
        .map { (label: $0.label, insert: "\($0.key):\($0.value)") }
    }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          tokens
          TextField("Search", text: $text)
            .autocorrectionDisabled()
            .onSubmit(run)
          chips
        }
        if Searches.modifierTyped(text) != nil {
          Section {
            if completions.isEmpty {
              Text(noMatches).foregroundStyle(.secondary)
            }
            ForEach(completions, id: \.insert) { completion in
              Button(completion.label) { complete(completion.insert) }
            }
          }
        } else if typed.isSearchable {
          Section {
            Button("Show results for \(summary(typed))", systemImage: "magnifyingglass", action: run)
          }
        } else {
          Text(NavigationText.searchHint).foregroundStyle(.secondary)
        }
        if !recent.isEmpty {
          Section {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, search in
              Button(summary(search), systemImage: "clock") {
                session.runSearch(search, record: true)
                dismiss()
              }
            }
          } header: {
            HStack {
              Text("Recent searches")
              Spacer()
              Button("Clear") { confirmingClear = true }.buttonStyle(.borderless)
            }
          }
        }
      }
      .themedForm(look, irc)
      .navigationTitle("Search")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Search", action: run).disabled(!typed.isSearchable)
        }
      }
      .confirmationDialog("Clear", isPresented: $confirmingClear) {
        Button("Clear", role: .destructive) { session.attempt("Clearing recent searches") { try await session.clearRecentSearches() } }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(NavigationText.clearSearchesConfirm)
      }
    }
    .frame(minWidth: 480, minHeight: 440)
    .onAppear {
      if let room { filters.in = room }
    }
  }

  private var noMatches: String {
    switch Searches.modifierTyped(text)?.key {
    case "in": "No rooms match."
    case "from": "No people match."
    default: "No filters match. Try has:link, has:file, is:thread or with:me."
    }
  }

  /** Recent searches: all with nothing typed, else those with the text, five at most (`suggestionsOf`). */
  private var recent: [Search] {
    let sought = text.trimmingCharacters(in: .whitespaces).lowercased()
    guard !sought.isEmpty else { return session.search.recent }
    return Array(session.search.recent.filter { $0.q.lowercased().contains(sought) }.prefix(5))
  }

  @ViewBuilder
  private var chips: some View {
    FlowLayout {
      if let room {
        chip(session.rooms.first { $0.id == room }?.room.isDirect == true ? "In this conversation" : "In this room", on: filters.in == room) {
          filters.in = filters.in == room ? nil : room
        }
      }
      if let me = session.me {
        chip("From me", on: filters.from == me.id) { filters.from = filters.from == me.id ? nil : me.id }
      }
      ForEach([Search.Flag.withMe, .hasLink, .inThread], id: \.self) { flag in
        chip(flag.label, on: filters.has(flag)) { filters.set(flag, !filters.has(flag)) }
      }
      if showingMore {
        chip(Search.Flag.hasFile.label, on: filters.has(.hasFile)) { filters.set(.hasFile, !filters.has(.hasFile)) }
        chip("From someone...", on: false) { text += (text.isEmpty || text.hasSuffix(" ") ? "" : " ") + "from:" }
        chip("In a room...", on: false) { text += (text.isEmpty || text.hasSuffix(" ") ? "" : " ") + "in:" }
      } else {
        Button("More Filters", systemImage: "plus") { showingMore = true }.labelStyle(.iconOnly).buttonStyle(.bordered)
      }
    }
  }

  private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .buttonStyle(.bordered)
      .tint(on ? Color.accentColor : Color.secondary)
      .accessibilityAddTraits(on ? .isSelected : [])
  }

  /**
   * Picks a completion: the modifier being typed becomes a token before the text, a room, a person or a
   * flag, which × takes off (web `SearchBox` tokens).
   */
  private func complete(_ insert: String) {
    var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    if !words.isEmpty { words.removeLast() }
    let (token, _) = session.typedSearch(insert)
    if token.in != nil || token.from != nil || Search.Flag.allCases.contains(where: token.has) {
      if let room = token.in { filters.in = room }
      if let from = token.from { filters.from = from }
      for flag in Search.Flag.allCases where token.has(flag) { filters.set(flag, true) }
    } else {
      // Not something a token holds: it stays typed.
      words.append(insert)
    }
    let kept = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    text = kept.isEmpty ? kept : kept + " "
  }

  /** The filters as removable tokens before the field. */
  @ViewBuilder
  private var tokens: some View {
    if filters.in != nil || filters.from != nil {
      FlowLayout {
        if let room = filters.in {
          tokenButton("in:\(SearchSummary.roomName(room, session: session))") { filters.in = nil }
        }
        if let from = filters.from {
          tokenButton(from == session.me?.id ? "from:me" : "from:\(session.people[from]?.name ?? from)") { filters.from = nil }
        }
      }
    }
  }

  private func tokenButton(_ title: String, remove: @escaping () -> Void) -> some View {
    Button(action: remove) { Label(title, systemImage: "xmark") }
      .buttonStyle(.bordered)
      .help("Take \(title) off")
  }

  private func summary(_ search: Search) -> String { SearchSummary.text(search, session: session) }

  private func run() {
    let (search, sort) = session.typedSearch(text)
    var full = typed
    full.q = search.q
    guard full.isSearchable else { return }
    session.runSearch(full, sort: sort ?? .newest)
    dismiss()
  }
}

/** A search as words and its filters' tokens, as the box's tokens and the results page's button show it. */
@MainActor
enum SearchSummary {
  /** A room a search is in, by the name this person reads it by. */
  static func roomName(_ room: RoomID, session: InstanceSession) -> String {
    if let listed = session.rooms.first(where: { $0.id == room }) { return session.title(of: listed.room) }
    if let found = session.search.rooms[room] { return session.title(of: found) }
    return room
  }

  static func text(_ search: Search, session: InstanceSession) -> String {
    var parts: [String] = []
    if let room = search.in {
      parts.append("in:\(roomName(room, session: session))")
    }
    if let from = search.from {
      parts.append(from == session.me?.id ? "from:me" : "from:\(session.people[from]?.name ?? from)")
    }
    for flag in Search.Flag.allCases where search.has(flag) { parts.append("\(flag.key):\(flag.value)") }
    if !search.q.isEmpty { parts.append(search.q) }
    return parts.joined(separator: " ")
  }
}

/**
 * The search page (web `SearchPage`): the search, its filters and sort, how many it found, and each
 * match with the words it matched marked and a way into its room.
 */
struct SearchResultsPage: View {
  let session: InstanceSession
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  private var model: SearchModel { session.search }

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: "Search", back: session.closePage) {
        Button(model.ran ? SearchSummary.text(model.search, session: session) : "Search") { session.openSearchBox(in: model.search.in) }
          .help("Change search")
        if model.ran {
          Menu(model.sort == .newest ? "Newest first" : "Oldest first") {
            Button("Newest first") { session.runSearch(model.search, sort: .newest, record: false) }
            Button("Oldest first") { session.runSearch(model.search, sort: .oldest, record: false) }
          }
          .fixedSize()
        }
      }
      if model.ran, model.search.isSearchable {
        filterRow
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: look == .irc ? 2 : Spacing.md) {
          if !model.ran {
            empty("Find a conversation", "Search messages across your rooms and direct messages.")
            recent
          } else if let error = model.error {
            Text(error).foregroundStyle(SemanticColor.warning)
          } else if model.matches.isEmpty, !model.busy {
            empty("No messages found", model.search.hasFilters ? "Try different words, or take a filter off." : "Try a different word or phrase.")
          } else {
            Text(model.countLabel).font(look == .irc ? Theme.font(12, weight: .bold) : DesignFont.sectionHeader)
            ForEach(Array(model.matches.enumerated()), id: \.element.message.id) { index, match in
              SearchMatchRow(session: session, match: match, number: index + 1)
            }
            if model.next != nil {
              Button(model.loadingMore ? "Loading..." : "Show more", action: session.moreResults).disabled(model.loadingMore)
            }
          }
        }
        .padding(look == .irc ? 12 : PaneGrid.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .loadingActivity(model.busy)
    }
    .font(look == .irc ? Theme.font(12) : DesignFont.body)
    .background(look == .irc ? irc.buffer : Color.clear)
  }

  /** The search's filters (web `SearchPage` filter row): its In and From scopes with ×, From me, and the flags, each a toggle. */
  private var filterRow: some View {
    let search = model.search
    return ScrollView(.horizontal) {
      HStack(spacing: Spacing.sm) {
        if let room = search.in {
          chip("In \(SearchSummary.roomName(room, session: session))", on: true, removable: true) { rerun { $0.in = nil } }
        }
        if let from = search.from, from != session.me?.id {
          chip("From \(session.people[from]?.name ?? from)", on: true, removable: true) { rerun { $0.from = nil } }
        }
        if let me = session.me?.id {
          chip("From me", on: search.from == me, removable: false) { rerun { $0.from = $0.from == me ? nil : me } }
        }
        ForEach(Search.Flag.allCases, id: \.self) { flag in
          chip(flag.label, on: search.has(flag), removable: false) { rerun { $0.set(flag, !$0.has(flag)) } }
        }
      }
      .padding(.horizontal, look == .irc ? 12 : PaneGrid.cardInset)
      .padding(.vertical, Spacing.sm)
    }
    .scrollIndicators(.hidden)
  }

  private func chip(_ title: String, on: Bool, removable: Bool, action: @escaping () -> Void) -> some View {
    Group {
      switch look {
      case .suite:
        Button(action: action) {
          if removable { Label(title, systemImage: "xmark").labelStyle(.titleAndIcon) } else { Text(title) }
        }
        .buttonStyle(.bordered)
        .tint(on ? Color.accentColor : Color.secondary)
      case .irc:
        Button(removable ? "[\(title) x]" : on ? "[*\(title)]" : "[\(title)]", action: action)
          .buttonStyle(.plain)
          .foregroundStyle(on ? irc.ember : irc.dim)
      }
    }
    .accessibilityAddTraits(on ? .isSelected : [])
    .help(removable ? "Take this filter off" : title)
  }

  /** Runs the search again with a filter changed, without recording it. */
  private func rerun(_ change: (inout Search) -> Void) {
    var search = model.search
    change(&search)
    guard search.isSearchable else { return }
    session.runSearch(search, sort: model.sort, record: false)
  }

  private func empty(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(look == .irc ? "-!- \(title)" : title).font(look == .irc ? Theme.font(13, weight: .bold) : DesignFont.cardTitle)
      Text(detail).foregroundStyle(.secondary)
      if !model.ran {
        Button("Search", systemImage: "magnifyingglass") { session.openSearchBox(in: nil) }
      }
    }
  }

  @ViewBuilder
  private var recent: some View {
    if !model.recent.isEmpty {
      Text("Recent searches").font(look == .irc ? Theme.font(12, weight: .bold) : DesignFont.sectionHeader).padding(.top, Spacing.md)
      ForEach(Array(model.recent.enumerated()), id: \.offset) { _, search in
        Button(SearchSummary.text(search, session: session)) { session.runSearch(search, record: true) }.buttonStyle(.plain)
      }
      Button("Clear", systemImage: "trash") { session.confirmation = .clearSearches }
    }
  }
}

/** One match (web result card): where it is, when, the message with its matched words marked, and View in room. */
struct SearchMatchRow: View {
  let session: InstanceSession
  let match: SearchMatch
  let number: Int
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  private var message: Message { match.message }
  private var isDirect: Bool {
    (session.rooms.first { $0.id == message.roomId }?.room ?? session.search.rooms[message.roomId])?.isDirect == true
  }

  var body: some View {
    switch look {
    case .suite:
      VStack(alignment: .leading, spacing: Spacing.sm) {
        HStack(spacing: Spacing.sm) {
          Image(systemName: isDirect ? "bubble.left" : "number").foregroundStyle(.secondary)
          Text(session.roomName(of: match)).font(DesignFont.bodyEmphasized)
          Text("·").foregroundStyle(.secondary)
          Text(message.createdDate.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
            .help(message.createdDate.formatted(date: .complete, time: .standard))
          Spacer()
          Button(isDirect ? "View in conversation" : "View in room", systemImage: "arrow.right") { session.open(match) }
            .buttonStyle(.borderless)
        }
        HStack(alignment: .top, spacing: Spacing.md) {
          SuiteAvatar(session: session, user: message.creator, size: 28)
          VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(session.people[message.creator.id]?.name ?? message.creator.name).font(DesignFont.bodyEmphasized)
            Text(marked(highlight: Color.accentColor.opacity(0.25))).textSelection(.enabled)
          }
        }
      }
      .padding(PaneGrid.cardInset)
      .background(SemanticColor.secondaryFill, in: RoundedRectangle(cornerRadius: Radius.card))
    case .irc:
      Button {
        session.open(match)
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("[\(number)]").foregroundStyle(irc.dim)
          Text("[\(Clock.time(message.createdDate, seconds: false))]").foregroundStyle(irc.dim)
          Text("<\(session.people[message.creator.id]?.name ?? message.creator.name)>").foregroundStyle(irc.nick(message.creator.id))
          Text(marked(highlight: irc.highlight.opacity(1))).foregroundStyle(irc.text)
          Text("(\(isDirect ? "" : "#")\(session.roomName(of: match)))").foregroundStyle(irc.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Open in its room, or /goto \(number)")
    }
  }

  /** The message's text with the words the search matched marked (`marksFor`). */
  private func marked(highlight: Color) -> AttributedString {
    let text = message.plainText
    var attributed = AttributedString(text)
    for range in Searches.marks(match.words, in: text) {
      guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
        let upper = AttributedString.Index(range.upperBound, within: attributed)
      else { continue }
      attributed[lower..<upper].backgroundColor = highlight
      attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
    }
    return attributed
  }
}
