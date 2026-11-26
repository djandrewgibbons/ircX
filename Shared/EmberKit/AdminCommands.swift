import Foundation

/**
 * IRC Classic's commands for workspace settings (the web's community settings), which open the same
 * Server Settings or do what its controls do. The Worker refuses whoever isn't an administrator.
 */
public enum AdminCommand: Equatable, Sendable {
  /** `/admin [general|rooms|membership|domain|bots|ai|huddles|styles]`: open Server Settings, at a section. */
  case open(String?)
  /** `/set name|tagline|restrict-rooms|hide-translations|icon …`: change a workspace setting. */
  case set(Setting)
  /** `/styles`: how long the custom CSS is; it's edited in Server Settings. */
  case styles
  /** `/order`, `/order #room n`, `/order save|cancel`: the shared room order. */
  case order(Order)
  /** `/join-mode [way on|off]`: the ways to join, or print them. */
  case joinMode(JoinWay?, Bool)
  /** `/joinlink [new]`: print the join link, or make a new one. */
  case joinLink(regenerate: Bool)
  /** `/domains [add …|del …|set …]`: Email domain's domains. */
  case domains(Domains)
  /** `/invite-email addresses`: invite by email. */
  case inviteEmail(String)
  /** `/invites [resend n|revoke n]`: the pending invitations. */
  case invites(Invites)
  /** `/mail [test|from mailbox|stop|setup]`: how Ember sends email. */
  case mail(Mail)
  /** `/turnstile [off|setup]` */
  case turnstile(Turnstile)
  /** `/memberful [on|off|only on|off|keys]` */
  case memberful(Provider)
  /** `/sso [on|off|only on|off|setup|remove]` */
  case sso(Provider)
  /** `/blocked [add words|del words]`: Blocked words. */
  case blocked(Blocked)
  /** `/reports [n dismiss|delete|remove|ban]` */
  case reports(Int?, ReportOutcome?)
  /** `/op nick`, `/deop nick`: make someone an administrator, or a member. */
  case role(String, administrator: Bool)
  /** `/kill nick`: remove someone from the workspace, after asking. */
  case remove(String)
  /** `/domain [check host|use [host]|reset|setup [host]]`: the custom domain. */
  case domain(Domain)
  /** `/version [check]`: the release this Ember is, asking GitHub afresh with check. */
  case version(check: Bool)
  /** `/reload`: start this server's session again, as the updated notice's Reload does. */
  case reload
  /** `/ai status|open|on|setup|off|models|default|add|rm|search|think|length|ember|prompt`, `/ai me …`: Ember AI. */
  case ai(AI)
  /** `/outside [on|off]`: whether AI apps may connect to Ember. */
  case outside(Bool?)
  /** `/agents`: the agents, for administrators; Available Agents for anyone else. */
  case agents
  /** `/agent new|rm|try|tools|tool …`, or `/agent name` to open its page. */
  case agent(AgentAction)
  /** `/apps admin|connect|edit|reread|rm …`: the apps Ember is connected to. */
  case app(AppAction)
  /** `/bots`: the chat bots and their rooms. */
  case bots
  /** `/bot new|urls|key|rm …`, or `/bot name` to open its page. */
  case bot(BotAction)
  /** `/huddles [on|off|keys|cameras on|off|screens on|off|relay on|off]` */
  case huddles(HuddlesAction)

  public enum AI: Equatable, Sendable {
    case status
    /** Open Server Settings' AI assistant section. */
    case open
    case setup
    case off
    case models
    case defaultModel(String)
    case add(String)
    case remove(String)
    case search(Bool)
    case think(ThinkingLevel)
    case length(AnswerLength)
    /** Open @ember's page: avatar, instructions, models, tools. */
    case ember
    /** Print what Ember tells @ember around its instructions. */
    case prompt
    /** Your own levels and model for @ember's answers. */
    case mine(ThinkingLevel?, AnswerLength?, model: String??)
  }

  public enum AgentAction: Equatable, Sendable {
    case new
    /** The agent named by the rest. */
    case open(String)
    case remove(String)
    /** An agent's name, then the question, as one line. */
    case trial(String)
    case tools(String)
    /** An agent's name, then `+app:tool`, `-app:tool`, `always app:tool` or `ask app:tool`. */
    case tool(String)
  }

  public enum AppAction: Equatable, Sendable {
    case list
    case connect
    case open(String)
    case reread(String)
    case remove(String)
    /** Sign Ember in to an app's server. */
    case signIn(String)
  }

  public enum BotAction: Equatable, Sendable {
    case new
    case open(String)
    case urls(String)
    case key(String)
    case remove(String)
  }

  public enum HuddlesAction: Equatable, Sendable {
    case status
    case on
    case off
    case keys
    case cameras(Bool)
    case screens(Bool)
    case relay(Bool)
  }

  /** The verbs `/ai` takes for administrators; anything else is your own outside AI's. */
  public static let aiVerbs: Set<String> = ["status", "open", "on", "setup", "off", "models", "default", "add", "rm", "remove", "search", "think", "length", "ember", "prompt", "me"]
  /** The verbs `/apps` takes for administrators; signin and signout are your own sign-ins. */
  public static let appVerbs: Set<String> = ["admin", "connect", "edit", "reread", "rm", "remove", "ember-signin"]

  public enum Setting: Equatable, Sendable {
    case name(String)
    case tagline(String)
    case restrictRooms(Bool)
    case hideTranslations(Bool)
    /** A slot's icon, or nil for its default. */
    case icon(NavigationSlot, String?)
  }

  public enum Order: Equatable, Sendable {
    case list
    case move(String, to: Int)
    case save
    case cancel
  }

  public enum Domains: Equatable, Sendable {
    case list
    case add([String])
    case remove([String])
    case set([String])
  }

  public enum Invites: Equatable, Sendable {
    case list
    case resend(Int)
    case revoke(Int)
  }

  public enum Mail: Equatable, Sendable {
    case status
    case test
    case from(String)
    case stop
    case setup
  }

  public enum Turnstile: Equatable, Sendable {
    case status
    case off
    case setup
  }

  public enum Provider: Equatable, Sendable {
    case status
    case on(Bool)
    case only(Bool)
    /** Set up Memberful's keys, or single sign-on. */
    case setup
    /** Remove single sign-on's saved provider. */
    case remove
  }

  public enum Blocked: Equatable, Sendable {
    case list
    case add(String)
    case remove(String)
  }

  public enum Domain: Equatable, Sendable {
    case status
    case check(String)
    case use(String?)
    case reset
    /** Open Set up, with the host typed in its field if one was given. */
    case setup(String?)
  }

  /** The sections `/admin` opens. */
  public static let sections = ["general", "rooms", "membership", "domain", "bots", "ai", "huddles", "styles"]

  public static let help =
    "Admin: /admin [general|rooms|membership|domain|bots|ai|huddles|styles] · /set name|tagline|restrict-rooms|hide-translations|icon … · /styles · /order [#room n|save|cancel] · /join-mode [way on|off] · /joinlink [new] · /domains [add|del|set …] · /invite-email addresses · /invites [resend|revoke n] · /mail [test|from|stop|setup] · /turnstile [off|setup] · /memberful [on|off|only on|off|keys] · /sso [on|off|only on|off|setup|remove] · /blocked [add|del words] · /reports [n dismiss|delete|remove|ban] · /op nick · /deop nick · /kill nick · /domain [check host|use [host]|reset|setup [host]] · /version [check] · /reload\n"
    + "AI: /ai status|on|setup|off|models|default id|add id|rm id|search on|off|think level|length level|ember|prompt · /ai me think|length|model … · /outside [on|off] · /agents · /agent new|name|rm name|try name question|tools name|tool name +app:tool|-app:tool|always app:tool|ask app:tool · /apps admin|connect|edit name|reread name|rm name|ember-signin name · /bots · /bot new|name|urls name|key name|rm name · /huddles [on|off|keys|cameras on|off|screens on|off|relay on|off]"

  /** The command named `name` with `rest` after it, or nil when `name` isn't one of these. */
  public static func parse(_ name: String, _ rest: String) -> InputCommand? {
    let words = rest.split(separator: " ").map(String.init)
    let first = words.first?.lowercased()
    let tail = words.dropFirst().joined(separator: " ")
    switch name {
    case "admin", "workspace":
      guard let first else { return .admin(.open(nil)) }
      guard sections.contains(first) else { return .unknown("/admin takes \(sections.joined(separator: ", "))") }
      return .admin(.open(first))
    case "set":
      switch first {
      case "name": return tail.isEmpty ? .unknown("/set name needs a name") : .admin(.set(.name(tail)))
      case "tagline": return .admin(.set(.tagline(tail)))
      case "restrict-rooms":
        guard let on = onOff(tail) else { return .unknown("/set restrict-rooms takes on or off") }
        return .admin(.set(.restrictRooms(on)))
      case "hide-translations":
        guard let on = onOff(tail) else { return .unknown("/set hide-translations takes on or off") }
        return .admin(.set(.hideTranslations(on)))
      case "icon":
        let pieces = tail.split(separator: " ").map(String.init)
        guard pieces.count == 2, let slot = NavigationSlot(rawValue: pieces[0].lowercased()) else {
          return .unknown("/set icon takes a slot (\(NavigationSlot.allCases.map(\.rawValue).joined(separator: ", "))) and an icon's name or default")
        }
        return .admin(.set(.icon(slot, pieces[1].lowercased() == "default" ? nil : pieces[1])))
      default: return .unknown("/set takes name, tagline, restrict-rooms, hide-translations or icon")
      }
    case "styles", "css": return .admin(.styles)
    case "order":
      switch first {
      case nil: return .admin(.order(.list))
      case "save": return .admin(.order(.save))
      case "cancel": return .admin(.order(.cancel))
      default:
        guard words.count == 2, let room = InputCommand.roomName(words[0]), let position = Int(words[1]), position > 0 else {
          return .unknown("/order takes #room and a position, save or cancel")
        }
        return .admin(.order(.move(room, to: position)))
      }
    case "join-mode", "joinmode":
      guard let first else { return .admin(.joinMode(nil, false)) }
      let ways: [String: JoinWay] = [
        "open": .openSignUp, "link": .joinLink, "domain": .emailDomainSignUp, "memberful": .memberfulJoin, "members-only": .memberfulSignIn,
        "sso": .ssoJoin, "sso-only": .ssoSignIn,
      ]
      guard let way = ways[first], let on = onOff(tail) else { return .unknown("/join-mode takes open, link, domain, memberful, members-only, sso or sso-only, then on or off") }
      return .admin(.joinMode(way, on))
    case "joinlink", "join-link":
      guard let first else { return .admin(.joinLink(regenerate: false)) }
      return first == "new" ? .admin(.joinLink(regenerate: true)) : .unknown("/joinlink takes new, or nothing")
    case "domains":
      let domains = words.dropFirst().flatMap { $0.split(whereSeparator: { $0 == "," || $0 == ";" }).map(String.init) }
      switch first {
      case nil: return .admin(.domains(.list))
      case "add": return domains.isEmpty ? .unknown("/domains add needs a domain") : .admin(.domains(.add(domains)))
      case "del", "remove": return domains.isEmpty ? .unknown("/domains del needs a domain") : .admin(.domains(.remove(domains)))
      case "set": return .admin(.domains(.set(domains)))
      default: return .unknown("/domains takes add, del or set")
      }
    case "invite-email", "inviteemail":
      return rest.isEmpty ? .unknown("/invite-email needs an email address") : .admin(.inviteEmail(rest))
    case "invites":
      switch first {
      case nil: return .admin(.invites(.list))
      case "resend", "revoke":
        guard words.count == 2, let n = Int(words[1]), n > 0 else { return .unknown("/invites \(words[0]) needs an invitation's number") }
        return .admin(.invites(first == "resend" ? .resend(n) : .revoke(n)))
      default: return .unknown("/invites takes resend n or revoke n")
      }
    case "mail":
      switch first {
      case nil: return .admin(.mail(.status))
      case "test": return .admin(.mail(.test))
      case "from": return tail.isEmpty ? .unknown("/mail from needs an address") : .admin(.mail(.from(tail)))
      case "stop": return .admin(.mail(.stop))
      case "setup": return .admin(.mail(.setup))
      default: return .unknown("/mail takes test, from, stop or setup")
      }
    case "turnstile":
      switch first {
      case nil: return .admin(.turnstile(.status))
      case "off": return .admin(.turnstile(.off))
      case "setup": return .admin(.turnstile(.setup))
      default: return .unknown("/turnstile takes off or setup")
      }
    case "memberful", "sso":
      let provider: Provider
      switch first {
      case nil: provider = .status
      case "on": provider = .on(true)
      case "off": provider = .on(false)
      case "only":
        guard let on = onOff(tail) else { return .unknown("/\(name) only takes on or off") }
        provider = .only(on)
      case "keys" where name == "memberful", "setup": provider = .setup
      case "remove" where name == "sso": provider = .remove
      default: return .unknown(name == "sso" ? "/sso takes on, off, only on|off, setup or remove" : "/memberful takes on, off, only on|off or keys")
      }
      return .admin(name == "sso" ? .sso(provider) : .memberful(provider))
    case "blocked":
      switch first {
      case nil: return .admin(.blocked(.list))
      case "add": return tail.isEmpty ? .unknown("/blocked add needs a word") : .admin(.blocked(.add(tail)))
      case "del", "remove": return tail.isEmpty ? .unknown("/blocked del needs a word") : .admin(.blocked(.remove(tail)))
      default: return .unknown("/blocked takes add or del")
      }
    case "reports":
      guard let first else { return .admin(.reports(nil, nil)) }
      guard let n = Int(first), n > 0 else { return .unknown("/reports takes a report's number, then dismiss, delete, remove or ban") }
      guard let action = words.dropFirst().first?.lowercased() else { return .admin(.reports(n, nil)) }
      let outcomes: [String: ReportOutcome] = ["dismiss": .dismissed, "delete": .deleted, "remove": .removed, "ban": .banned]
      guard let outcome = outcomes[action] else { return .unknown("/reports n takes dismiss, delete, remove or ban") }
      return .admin(.reports(n, outcome))
    case "op": return rest.isEmpty ? .unknown("/op needs a nick") : .admin(.role(rest, administrator: true))
    case "deop": return rest.isEmpty ? .unknown("/deop needs a nick") : .admin(.role(rest, administrator: false))
    case "kill": return rest.isEmpty ? .unknown("/kill needs a nick") : .admin(.remove(rest))
    case "domain":
      switch first {
      case nil: return .admin(.domain(.status))
      case "check": return tail.isEmpty ? .unknown("/domain check needs a host") : .admin(.domain(.check(tail)))
      case "use": return .admin(.domain(.use(tail.isEmpty ? nil : tail)))
      case "reset": return .admin(.domain(.reset))
      case "setup": return .admin(.domain(.setup(tail.isEmpty ? nil : tail)))
      default: return .unknown("/domain takes check, use, reset or setup")
      }
    case "version": return .admin(.version(check: first == "check"))
    case "reload": return .admin(.reload)
    case "ai": return ai(words, tail)
    case "outside":
      guard let first else { return .admin(.outside(nil)) }
      guard let on = onOff(first) else { return .unknown("/outside takes on or off") }
      return .admin(.outside(on))
    case "agents": return .admin(.agents)
    case "agent":
      guard let first else { return .unknown("/agent takes new, an agent's name, rm, try, tools or tool") }
      let named = { (verb: String, make: (String) -> AgentAction) -> InputCommand in
        tail.isEmpty ? .unknown("/agent \(verb) needs an agent's name") : .admin(.agent(make(tail)))
      }
      switch first {
      case "new": return .admin(.agent(.new))
      case "rm", "del", "delete": return named(first, AgentAction.remove)
      case "try": return named(first, AgentAction.trial)
      case "tools": return named(first, AgentAction.tools)
      case "tool": return named(first, AgentAction.tool)
      default: return .admin(.agent(.open(rest)))
      }
    case "apps", "app":
      let named = { (verb: String, make: (String) -> AppAction) -> InputCommand in
        tail.isEmpty ? .unknown("/apps \(verb) needs an app's name") : .admin(.app(make(tail)))
      }
      switch first {
      case "admin": return .admin(.app(.list))
      case "connect": return .admin(.app(.connect))
      case "edit": return named("edit", AppAction.open)
      case "reread": return named("reread", AppAction.reread)
      case "rm", "remove": return named("rm", AppAction.remove)
      case "ember-signin": return named("ember-signin", AppAction.signIn)
      default: return nil
      }
    case "bots": return .admin(.bots)
    case "bot":
      guard let first else { return .unknown("/bot takes new, a bot's name, urls, key or rm") }
      let named = { (verb: String, make: (String) -> BotAction) -> InputCommand in
        tail.isEmpty ? .unknown("/bot \(verb) needs a bot's name") : .admin(.bot(make(tail)))
      }
      switch first {
      case "new": return .admin(.bot(.new))
      case "urls", "url": return named("urls", BotAction.urls)
      case "key": return named("key", BotAction.key)
      case "rm", "del", "delete": return named("rm", BotAction.remove)
      default: return .admin(.bot(.open(rest)))
      }
    case "huddles":
      switch first {
      case nil: return .admin(.huddles(.status))
      case "on", "setup": return .admin(.huddles(.on))
      case "off": return .admin(.huddles(.off))
      case "keys": return .admin(.huddles(.keys))
      case "cameras", "screens", "relay":
        guard let on = onOff(tail) else { return .unknown("/huddles \(words[0]) takes on or off") }
        return .admin(.huddles(first == "cameras" ? .cameras(on) : first == "screens" ? .screens(on) : .relay(on)))
      default: return .unknown("/huddles takes on, off, keys, cameras, screens or relay")
      }
    default: return nil
    }
  }

  /** `/ai …`, an administrator's verbs, and `/ai me …`, anyone's own. */
  private static func ai(_ words: [String], _ tail: String) -> InputCommand {
    let first = words.first?.lowercased()
    let second = words.dropFirst().first?.lowercased()
    switch first {
    case nil, "status": return .admin(.ai(.status))
    case "open": return .admin(.ai(.open))
    // Turning Ember AI on is its setup, as the web's switch opens it.
    case "setup", "on": return .admin(.ai(.setup))
    case "off": return .admin(.ai(.off))
    case "models": return .admin(.ai(.models))
    case "default": return tail.isEmpty ? .unknown("/ai default needs a model's id") : .admin(.ai(.defaultModel(tail)))
    case "add": return tail.isEmpty ? .unknown("/ai add needs a model's id") : .admin(.ai(.add(tail)))
    case "rm", "remove": return tail.isEmpty ? .unknown("/ai rm needs a model's id") : .admin(.ai(.remove(tail)))
    case "search":
      guard let on = onOff(tail) else { return .unknown("/ai search takes on or off") }
      return .admin(.ai(.search(on)))
    case "think":
      guard let level = second.flatMap(ThinkingLevel.init(rawValue:)) else { return .unknown("/ai think takes off, low, medium or high") }
      return .admin(.ai(.think(level)))
    case "length":
      guard let length = second.flatMap(AnswerLength.init(rawValue:)) else { return .unknown("/ai length takes short, medium or long") }
      return .admin(.ai(.length(length)))
    case "ember": return .admin(.ai(.ember))
    case "prompt": return .admin(.ai(.prompt))
    case "me":
      let rest = Array(words.dropFirst(2))
      switch second {
      case nil: return .admin(.ai(.mine(nil, nil, model: nil)))
      case "think":
        guard let level = rest.first.flatMap({ ThinkingLevel(rawValue: $0.lowercased()) }) else { return .unknown("/ai me think takes off, low, medium or high") }
        return .admin(.ai(.mine(level, nil, model: nil)))
      case "length":
        guard let length = rest.first.flatMap({ AnswerLength(rawValue: $0.lowercased()) }) else { return .unknown("/ai me length takes short, medium or long") }
        return .admin(.ai(.mine(nil, length, model: nil)))
      case "model":
        guard let model = rest.first else { return .unknown("/ai me model takes a model's id, or default") }
        return .admin(.ai(.mine(nil, nil, model: .some(model.lowercased() == "default" ? nil : model))))
      default: return .unknown("/ai me takes think, length or model")
      }
    default: return .unknown("/ai takes status, on, setup, off, models, default, add, rm, search, think, length, ember, prompt, me or disconnect")
    }
  }

  private static func onOff(_ text: String) -> Bool? {
    switch text.lowercased() {
    case "on", "yes", "true": true
    case "off", "no", "false": false
    default: nil
    }
  }
}

extension AdminCommand {
  /**
   * What the Worker answers someone who isn't an administrator for this command (its 403s'
   * `*_FORBIDDEN`), which the input line prints rather than asking.
   */
  public var forbidden: String {
    switch self {
    case .ai: "Only administrators can set up Ember AI"
    case .agents, .agent: "Only administrators can set up agents"
    case .app: "Only administrators can connect apps"
    case .bots, .bot: "Only administrators can manage bots"
    case .huddles: "Only administrators can set up huddles"
    case .outside: "Only administrators can change whether AI apps connect"
    case .sso: "Only administrators can set up single sign-on"
    case .reports: "Only administrators can see reports"
    case .role: "Only administrators can change people's roles"
    case .remove: "Only administrators can remove people"
    case .inviteEmail, .invites: "Only administrators can invite people"
    default: "Only administrators can change the workspace"
    }
  }
}
