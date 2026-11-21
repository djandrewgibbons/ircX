import Foundation

// Every endpoint the web app calls (apps/web/src/lib/api.ts), by area, named after the web's calls.

extension EmberAPI {
  private func id(_ value: String) -> String { URIComponent.encode(value) }

  // MARK: - Session, bootstrap, setup, joining

  public func bootstrap() async throws -> Bootstrap { try await get("/api/bootstrap") }

  /** `GET /api/me`: who the session signs in as. */
  public func me() async throws -> Me { try await get("/api/me", as: UserAnswer.self).user }

  /** Signs in with an email address and password, or says where to connect an account (202). */
  public func signIn(emailAddress: String, password: String) async throws -> PasswordSignInAnswer {
    let (data, http) = try await send(jsonRequest("POST", "/api/session", PasswordSignIn(emailAddress: emailAddress, password: password)))
    if http.statusCode == 202 {
      return .elsewhere(ElsewhereStart(connection: try decode(data, from: "/api/session"), cookies: StateCookie.all(in: http)))
    }
    let answer: UserAnswer = try decode(data, from: "/api/session")
    guard isSignedIn else { throw EmberError.noSession }
    return .signedIn(answer.user)
  }

  /** Signs in with just a name, where the instance lets guests in (`Bootstrap.guestSignIn`). */
  public func signIn(name: String) async throws -> Me {
    let answer: UserAnswer = try await write("POST", "/api/session", json: ["name": name])
    guard isSignedIn else { throw EmberError.noSession }
    return answer.user
  }

  /**
   * Signs in with a sign-in link from someone's profile, such as `https://irc.dxnd.ai/session/transfers#token=abc`,
   * which the QR code there holds.
   */
  public func signIn(transferLink: String) async throws -> Me {
    guard let id = SessionCookie.transferId(in: transferLink) else { throw EmberError.refused(422, "That isn't a sign-in link.") }
    let answer: UserAnswer
    do {
      answer = try await write("POST", "/api/session/transfers", json: ["transferId": id])
    } catch let EmberError.problem(problem) where problem.status == 400 {
      // Ember answers a link that's expired, tampered with or someone's who can't sign in with no words.
      throw EmberError.problem(EmberProblem(status: 400, message: PeopleText.transferRefused))
    }
    guard isSignedIn else { throw EmberError.noSession }
    return answer.user
  }

  /** Signs out (`DELETE /api/session`), forgetting the session here once Ember has, or once it's gone already. */
  public func signOut(pushSubscriptionEndpoint: String? = nil) async throws {
    do {
      try await perform("DELETE", "/api/session", json: SignOut(pushSubscriptionEndpoint: pushSubscriptionEndpoint))
    } catch EmberError.signedOut {
      // Ended elsewhere already.
    }
    tokens.setToken(nil, for: instance.id)
  }

  /** `POST /api/first_run/check`: whether the setup password is right. */
  public func checkSetupPassword(_ password: String) async throws {
    var request = request("/api/first_run/check", method: "POST")
    request.setValue("Bearer \(URIComponent.encode(password))", forHTTPHeaderField: "Authorization")
    try await send(request)
  }

  /** `POST /api/first_run`: makes the workspace and its first administrator, who's signed in. */
  public func setUpWorkspace(_ administrator: SignUp, photo: ChosenPhoto? = nil, setupSecret: String? = nil) async throws -> NewWorkspace {
    var request = try userRequest("POST", "/api/first_run", administrator, photo: photo)
    if let setupSecret { request.setValue("Bearer \(URIComponent.encode(setupSecret))", forHTTPHeaderField: "Authorization") }
    let (data, _) = try await send(request)
    return try decode(data, from: "/api/first_run")
  }

  /** `POST /api/join/<code>`: joins with the join link's code. */
  public func join(code: String, _ person: SignUp, photo: ChosenPhoto? = nil) async throws -> Me {
    try await signedUp(userRequest("POST", "/api/join/\(id(code))", person, photo: photo))
  }

  /** `POST /api/join`: open sign-up. */
  public func signUp(_ person: SignUp, photo: ChosenPhoto? = nil) async throws -> Me {
    try await signedUp(userRequest("POST", "/api/join", person, photo: photo))
  }

  /** `POST /api/email_links/lookup`: whom an emailed link is for. */
  public func lookUpEmailLink(token: String) async throws -> EmailLinkFor {
    try await write("POST", "/api/email_links/lookup", json: ["token": token])
  }

  /** Joins with an emailed link (`/api/join/invitation` or `/api/join/email`). */
  public func join(with kind: EmailLinkKind, _ person: EmailLinkSignUp, photo: ChosenPhoto? = nil) async throws -> Me {
    try await signedUp(userRequest("POST", kind.joinPath, person, photo: photo))
  }

  /** `POST /api/email_links`: asks for a link to join with an email domain's address. */
  public func askForEmailLink(_ asked: EmailRequest) async throws { try await perform("POST", "/api/email_links", json: asked) }

  /** `POST /api/password_resets`: asks for a code. */
  public func askForPasswordResetCode(_ asked: EmailRequest) async throws { try await perform("POST", "/api/password_resets", json: asked) }

  /** `PUT /api/password_resets`: signed in, or nil for someone who signs in elsewhere. */
  public func resetPassword(_ reset: PasswordResetWithCode) async throws -> Me? {
    let done: PasswordResetDone = try await write("PUT", "/api/password_resets", json: reset)
    return done.user
  }

  private func userRequest(_ method: String, _ path: String, _ fields: some Encodable, photo: ChosenPhoto?) throws -> URLRequest {
    guard let photo else { return try jsonRequest(method, path, fields) }
    return formRequest(method, path, form: try MultipartForm.photo(photo, user: fields))
  }

  private func signedUp(_ request: URLRequest) async throws -> Me {
    let (data, _) = try await send(request)
    let answer: UserAnswer = try decode(data, from: request.url?.path ?? "/api/join")
    guard isSignedIn else { throw EmberError.noSession }
    return answer.user
  }

  // MARK: - Sidebar, rooms, directory

  public func sidebar() async throws -> Sidebar { try await get("/api/sidebar") }
  public func directory() async throws -> Directory { try await get("/api/users") }
  /** `GET /api/rooms/new`: the people a new room can have. */
  public func people() async throws -> NewRoomForm { try await get("/api/rooms/new") }

  /** `DELETE /api/sidebar/invitation`: dismisses the welcome card. */
  public func dismissInvitation() async throws { try await perform("DELETE", "/api/sidebar/invitation") }

  /** `POST /api/directs`: the DM with these people, and whether it's new (201) or theirs already (200). */
  public func startDirect(with userIds: [UserID]) async throws -> (room: Room, isNew: Bool) {
    let (data, http) = try await send(jsonRequest("POST", "/api/directs", ["userIds": userIds]))
    let answer: StartedDirect = try decode(data, from: "/api/directs")
    return (answer.room, http.statusCode == 201)
  }

  public func createRoom(_ room: NewRoom) async throws -> Room {
    try await write("POST", "/api/rooms", json: room, as: RoomAnswer.self).room
  }

  public func roomSettings(_ room: RoomID) async throws -> RoomSettings { try await get("/api/rooms/\(id(room))/settings") }

  public func changeRoom(_ room: RoomID, _ changes: RoomChanges) async throws -> Room {
    try await write("PATCH", "/api/rooms/\(id(room))", json: changes, as: RoomAnswer.self).room
  }

  public func deleteRoom(_ room: RoomID) async throws { try await perform("DELETE", "/api/rooms/\(id(room))") }
  /** Leaves a private room. */
  public func leaveRoom(_ room: RoomID) async throws { try await perform("DELETE", "/api/rooms/\(id(room))/membership") }

  @discardableResult
  public func setFavorite(_ favorite: Bool, room: RoomID) async throws -> Favorites {
    struct Answer: Decodable { let favorites: Favorites }
    return try await write("PUT", "/api/rooms/\(id(room))/favorite", json: ["favorite": favorite], as: Answer.self).favorites
  }

  @discardableResult
  public func setInvolvement(_ involvement: Involvement, in room: RoomID) async throws -> Involvement {
    struct Answer: Decodable { let involvement: Involvement }
    return try await write("PUT", "/api/rooms/\(id(room))/involvement", json: ["involvement": involvement.rawValue], as: Answer.self).involvement
  }

  /** `PUT /api/sidebar/order`: the starred rooms in a new order, exactly those starred. */
  public func setFavoriteOrder(_ roomIds: [RoomID]) async throws -> Favorites {
    struct Answer: Decodable { let favorites: Favorites }
    return try await write("PUT", "/api/sidebar/order", json: ["roomIds": roomIds], as: Answer.self).favorites
  }

  /** `PUT /api/account/room_order`: the workspace's room order; [] clears it. */
  public func setSharedOrder(_ roomIds: [RoomID]) async throws -> [RoomID] {
    struct Answer: Decodable { let sharedOrder: [RoomID] }
    return try await write("PUT", "/api/account/room_order", json: ["roomIds": roomIds], as: Answer.self).sharedOrder
  }

  /** `GET /api/users/<id>` */
  public func person(_ user: UserID) async throws -> PersonAnswer { try await get("/api/users/\(id(user))") }

  /** `GET /api/autocompletable/users`: whom the @ prompt offers in a room, the first 20 by name. */
  public func mentionable(in room: RoomID?, filter: String) async throws -> [MentionPromptItem] {
    var query: [String] = []
    if let room { query.append("room_id=\(id(room))") }
    if !filter.isEmpty { query.append("filter=\(id(filter))") }
    var request = request("/api/autocompletable/users" + (query.isEmpty ? "" : "?" + query.joined(separator: "&")))
    request.setValue("text/html", forHTTPHeaderField: "Accept")
    let (data, _) = try await send(request)
    return try MentionPrompt.items(in: String(decoding: data, as: UTF8.self))
  }

  /** `GET /api/agents`: the agents people can ask. */
  public func availableAgents() async throws -> [AvailableAgent] { try await get("/api/agents", as: AvailableAgents.self).agents }

  // MARK: - Messages: files, search, previews

  /** `POST /api/rooms/<id>/uploads`: starts an upload. */
  public func beginUpload(_ upload: NewUpload, in room: RoomID) async throws -> Upload {
    try await write("POST", Files.uploadsPath(room), json: upload)
  }

  /** `PUT .../parts/<n>`: sends part `n` (from 1); the last answers the file's message. */
  public func uploadPart(_ data: Data, number: Int, of upload: Upload, in room: RoomID) async throws -> Message? {
    var request = request(Files.uploadPartPath(room, upload.id, number), method: "PUT", timeout: 300)
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.httpBody = data
    let (body, http) = try await send(request)
    guard http.statusCode != 204 else { return nil }
    return try decode(body, from: Files.uploadPartPath(room, upload.id, number))
  }

  /** `PUT .../preview`: a file's preview, before its last part. */
  public func uploadPreview(_ data: Data, contentType: String, of upload: Upload, in room: RoomID) async throws {
    var request = request(Files.uploadPreviewPath(room, upload.id), method: "PUT", timeout: 120)
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    request.httpBody = data
    try await send(request)
  }

  /** `GET /api/searches`: a page of results, not recorded as a recent search. */
  public func search(_ search: Search, sort: SearchSort = .newest, cursor: Int? = nil) async throws -> SearchResults {
    try await get("/api/searches?\(Searches.query(search, sort: sort, cursor: cursor))")
  }

  /** `POST /api/searches`: the first page, recorded as the newest recent search. */
  public func recordSearch(_ search: Search, sort: SearchSort = .newest) async throws -> SearchResults {
    struct Body: Encodable {
      let search: Search
      let sort: SearchSort
      func encode(to encoder: Encoder) throws {
        try search.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(sort, forKey: .sort)
      }
      enum Keys: String, CodingKey { case sort }
    }
    return try await write("POST", "/api/searches", json: Body(search: search, sort: sort))
  }

  public func clearSearches() async throws { try await perform("DELETE", "/api/searches") }

  /** `POST /api/unfurl`: a link's preview, or nil when it has none (204). */
  public func linkPreview(_ url: String) async throws -> LinkPreview? {
    let (data, http) = try await send(jsonRequest("POST", "/api/unfurl", ["url": url]))
    guard http.statusCode != 204 else { return nil }
    return try decode(data, from: "/api/unfurl")
  }

  // MARK: - Profile and people

  public func profile() async throws -> ProfileAnswer { try await get("/api/users/me/profile") }
  public func changeProfile(_ changes: ProfileChanges) async throws -> ProfileAnswer { try await write("PATCH", "/api/users/me/profile", json: changes) }

  public func changeAvatar(_ photo: ChosenPhoto) async throws -> ProfileAnswer {
    let (data, _) = try await send(formRequest("PUT", Avatars.avatarPath, form: try MultipartForm.photo(photo)))
    return try decode(data, from: Avatars.avatarPath)
  }

  public func removeAvatar() async throws -> ProfileAnswer { try await write("DELETE", Avatars.avatarPath) }

  /**
   * `DELETE /api/users/me`, after which the session is gone. A refusal (wrong password, only
   * administrator, too many tries) or a network failure keeps the session and its token.
   */
  public func deleteAccount(_ deletion: AccountDeletion) async throws {
    try await perform("DELETE", "/api/users/me", json: deletion)
    tokens.setToken(nil, for: instance.id)
  }

  /** Starts connecting a Memberful account: where to sign in there, and the state cookie its callback checks. */
  public func connectMemberful(currentPassword: String? = nil) async throws -> ElsewhereStart {
    try await connect(Memberful.connectionsPath, currentPassword)
  }

  public func disconnectMemberful(_ disconnection: Disconnection) async throws -> ProfileAnswer {
    try await write("DELETE", Memberful.connectionsPath, json: disconnection)
  }

  public func connectSso(currentPassword: String? = nil) async throws -> ElsewhereStart {
    try await connect(SSO.connectionsPath, currentPassword)
  }

  private func connect(_ path: String, _ currentPassword: String?) async throws -> ElsewhereStart {
    let (data, http) = try await send(jsonRequest("POST", path, ConnectionStart(currentPassword: currentPassword)))
    return ElsewhereStart(connection: try decode(data, from: path), cookies: StateCookie.all(in: http))
  }

  public func disconnectSso(_ disconnection: Disconnection) async throws -> ProfileAnswer {
    try await write("DELETE", SSO.connectionsPath, json: disconnection)
  }

  public func changeYourAssistant(_ changes: YourAssistantChanges) async throws -> YourAssistant? {
    try await write("PATCH", "/api/users/me/assistant", json: changes, as: YourAssistantChanged.self).assistant
  }

  public func changeHuddleSounds(_ changes: HuddleSoundChanges) async throws -> HuddleSounds {
    try await write("PATCH", "/api/users/me/huddle-sounds", json: changes, as: HuddleSoundsChanged.self).sounds
  }

  /** Starts your own sign-in to a connected app: the address to sign in at. */
  public func beginOwnAppSignIn(_ app: AppID) async throws -> String {
    try await write("POST", "/api/users/me/apps/\(id(app))/sign-in", as: AppSignInBegun.self).authorizationUrl
  }

  public func signOutOfApp(_ app: AppID) async throws -> YourAppSignedOut { try await write("DELETE", "/api/users/me/apps/\(id(app))/sign-in") }

  public func disconnectOutside(_ connection: String) async throws -> YourOutsideAi { try await write("DELETE", "/api/users/me/outside/\(id(connection))") }

  public func changeRole(_ user: UserID, to role: PersonRole) async throws -> DirectoryUser {
    try await write("PATCH", "/api/account/users/\(id(user))", json: RoleChange(role: role), as: ChangedPerson.self).user
  }

  public func removePerson(_ user: UserID) async throws -> DirectoryUser { try await write("DELETE", "/api/account/users/\(id(user))", as: ChangedPerson.self).user }
  public func ban(_ user: UserID) async throws -> DirectoryUser { try await write("POST", "/api/users/\(id(user))/ban", as: ChangedPerson.self).user }
  public func unban(_ user: UserID) async throws -> DirectoryUser { try await write("DELETE", "/api/users/\(id(user))/ban", as: ChangedPerson.self).user }

  /** Blocks or unblocks someone. */
  public func setBlocked(_ blocked: Bool, _ user: UserID) async throws -> ChangedBlocks {
    try await write(blocked ? "POST" : "DELETE", "/api/users/\(id(user))/block")
  }

  public func report(message: String, in room: RoomID, _ report: NewReport) async throws {
    try await perform("POST", "/api/rooms/\(id(room))/messages/\(id(message))/report", json: report)
  }

  public func report(person: UserID, _ report: NewReport) async throws {
    try await perform("POST", "/api/users/\(id(person))/report", json: report)
  }

  public func reports() async throws -> Reports { try await get("/api/reports") }

  public func handleReport(_ report: String, outcome: ReportOutcome) async throws -> [Report] {
    try await write("POST", "/api/reports/\(id(report))", json: ["outcome": outcome.rawValue], as: HandledReports.self).reports
  }

  // MARK: - Push

  public func pushSubscriptions() async throws -> [SavedPushSubscription] { try await get("/api/push-subscriptions", as: PushSubscriptions.self).subscriptions }
  /** `POST /api/push-subscriptions`: saves a browser's push subscription. */
  public func savePushSubscription(_ save: PushSubscriptionSave) async throws { try await perform("POST", "/api/push-subscriptions", json: save) }
  public func deletePushSubscription(_ subscription: Int) async throws { try await perform("DELETE", "/api/push-subscriptions/\(subscription)") }
  public func testPushSubscription(_ subscription: Int) async throws { try await perform("POST", "/api/push-subscriptions/\(subscription)/test-notifications") }

  /** `GET /api/device-tokens`: this person's ircX devices. */
  public func deviceTokens() async throws -> [DeviceToken] { try await get("/api/device-tokens", as: DeviceTokens.self).deviceTokens }
  /** `POST /api/device-tokens`: saves this device's APNs token, answering the device as saved. */
  public func saveDeviceToken(_ save: DeviceTokenSave) async throws -> DeviceToken { try await write("POST", "/api/device-tokens", json: save, as: DeviceToken.self) }
  public func deleteDeviceToken(_ token: Int) async throws { try await perform("DELETE", "/api/device-tokens/\(token)") }
  public func testDeviceToken(_ token: Int) async throws { try await perform("POST", "/api/device-tokens/\(token)/test-notifications") }

  // MARK: - Huddles

  /** `GET /api/huddles`: the huddles that are over, latest first. */
  public func pastHuddles() async throws -> [PastHuddle] { try await get("/api/huddles", as: PastHuddles.self).huddles }

  /** Stops a huddle invitation ringing on every device. */
  public func answerHuddleInvitation(in room: RoomID) async throws { try await perform("DELETE", "/api/rooms/\(id(room))/huddle/invitation") }

  // MARK: - Workspace settings (administrators; members read `workspaceSettings`)

  public func workspaceSettings() async throws -> WorkspaceSettings { try await get("/api/account") }

  public func changeAccount(_ changes: AccountChanges) async throws -> Account {
    try await write("PATCH", "/api/account", json: changes, as: AccountAnswer.self).account
  }

  public func checkCustomDomain(_ domain: String) async throws -> CustomDomainReach {
    try await write("POST", "/api/account/custom_domain_checks", json: DomainQuery(domain: domain), as: CustomDomainCheck.self).reaches
  }

  public func lookUpCustomDomain(_ domain: String) async throws -> CustomDomainLookup {
    try await write("POST", "/api/account/custom_domain_lookups", json: DomainQuery(domain: domain))
  }

  public func releaseCheck() async throws -> ReleaseCheck { try await get("/api/account/release") }
  public func checkForReleaseAfresh() async throws -> ReleaseCheck { try await write("POST", "/api/account/release_checks") }

  public func changeLogo(_ logo: ChosenLogo) async throws -> Account {
    var form = MultipartForm()
    form.add("logo", file: logo.data, fileName: logo.fileName, contentType: logo.contentType)
    if let large = logo.large { form.add("large", file: large, fileName: "large", contentType: logo.variantContentType) }
    if let small = logo.small { form.add("small", file: small, fileName: "small", contentType: logo.variantContentType) }
    let (data, _) = try await send(formRequest("PUT", Avatars.logoPath, form: form.finished()))
    return try decode(data, from: Avatars.logoPath, as: AccountAnswer.self).account
  }

  public func removeLogo() async throws -> Account { try await write("DELETE", Avatars.logoPath, as: AccountAnswer.self).account }

  public func customStyles() async throws -> String { try await get("/api/account/custom_styles", as: CustomStyles.self).customStyles }

  public func changeCustomStyles(_ customStyles: String) async throws -> Account {
    try await write("PATCH", "/api/account/custom_styles", json: CustomStyles(customStyles: customStyles), as: AccountAnswer.self).account
  }

  public func regenerateJoinCode() async throws -> String { try await write("POST", "/api/account/join_code", as: NewJoinCode.self).joinCode }
  /** Sends a test email to you: the address it went to. */
  public func sendTestEmail() async throws -> String { try await write("POST", "/api/account/test_email", as: SentTestEmail.self).to }

  public func checkSendingDomain(_ domain: String) async throws -> Bool? {
    try await write("POST", "/api/account/sending_domain_checks", json: DomainQuery(domain: domain), as: SendingDomainCheck.self).onboarded
  }

  public func saveResendApiKey(_ apiKey: String) async throws -> EmailSettings { try await write("PUT", "/api/account/resend_api_key", json: ["apiKey": apiKey]) }
  public func forgetResendApiKey() async throws -> EmailSettings { try await write("DELETE", "/api/account/resend_api_key") }

  public func saveTurnstileKeys(_ keys: TurnstileKeysChange) async throws -> KeySource? {
    try await write("PUT", "/api/account/turnstile_keys", json: keys, as: TurnstileSettings.self).turnstile
  }

  public func forgetTurnstileKeys() async throws -> KeySource? { try await write("DELETE", "/api/account/turnstile_keys", as: TurnstileSettings.self).turnstile }

  public func saveMemberfulKeys(_ keys: MemberfulKeysChange) async throws -> MemberfulSaved { try await write("PUT", "/api/account/memberful_keys", json: keys) }

  public func saveHuddles(_ setup: HuddlesSetup) async throws -> HuddlesSettings? {
    try await write("PUT", "/api/account/huddles", json: setup, as: HuddlesAnswer.self).huddles
  }

  public func forgetHuddles() async throws { _ = try await write("DELETE", "/api/account/huddles", as: HuddlesAnswer.self) }

  public func saveHuddleRelay(_ setup: HuddleRelaySetup) async throws -> HuddlesSettings? {
    try await write("PUT", "/api/account/huddles/relay", json: setup, as: HuddlesAnswer.self).huddles
  }

  public func forgetHuddleRelay() async throws -> HuddlesSettings? { try await write("DELETE", "/api/account/huddles/relay", as: HuddlesAnswer.self).huddles }

  public func saveSso(_ setup: SsoSetup) async throws -> SsoSettings? { try await write("PUT", SSO.settingsPath, json: setup, as: SsoAnswer.self).sso }
  public func forgetSso() async throws -> SsoSettings? { try await write("DELETE", SSO.settingsPath, as: SsoAnswer.self).sso }

  public func invite(_ emailAddresses: [String]) async throws -> [InvitationOutcome] {
    try await write("POST", "/api/invitations", json: ["emailAddresses": emailAddresses], as: Invited.self).outcomes
  }

  public func resendInvitation(_ invitation: String) async throws -> ResentInvitation { try await write("POST", "/api/invitations/\(id(invitation))/resend") }
  public func revokeInvitation(_ invitation: String) async throws { try await perform("DELETE", "/api/invitations/\(id(invitation))") }

  // MARK: - Ember AI (administrators)

  public func offeredModels(_ keys: AssistantSetup? = nil) async throws -> OfferedModels {
    let path = "/api/account/assistant/offered"
    guard let keys else { return try await write("POST", path, json: Empty(), timeout: Self.modelTimeout) }
    return try await write("POST", path, json: keys, timeout: Self.modelTimeout)
  }

  public func saveAssistant(_ setup: AssistantSetup) async throws -> AssistantSaved {
    try await write("PUT", "/api/account/assistant", json: setup, timeout: Self.modelTimeout)
  }

  public func addAssistantModel(_ model: String) async throws -> AssistantSaved {
    try await write("POST", "/api/account/assistant/models", json: ["model": model], timeout: Self.modelTimeout)
  }

  public func removeAssistantModel(_ model: String) async throws -> AssistantSettings? {
    try await write("DELETE", "/api/account/assistant/models", json: ["model": model], as: AssistantChanged.self).assistant
  }

  public func changeAssistantAvatar(_ photo: ChosenPhoto) async throws -> AssistantSettings? {
    let (data, _) = try await send(formRequest("PUT", "/api/account/assistant/avatar", form: try MultipartForm.photo(photo)))
    return try decode(data, from: "/api/account/assistant/avatar", as: AssistantChanged.self).assistant
  }

  public func removeAssistantAvatar() async throws -> AssistantSettings? { try await write("DELETE", "/api/account/assistant/avatar", as: AssistantChanged.self).assistant }
  public func forgetAssistant() async throws { _ = try await write("DELETE", "/api/account/assistant", as: AssistantChanged.self) }

  public func changeAssistantSettings(_ changes: AssistantChanges) async throws -> AssistantSettings? {
    try await write("PATCH", "/api/account/assistant", json: changes, timeout: Self.modelTimeout, as: AssistantChanged.self).assistant
  }

  public func changeWebSearch(_ on: Bool) async throws -> WebSearchChanged {
    try await write("PUT", "/api/account/assistant/web_search", json: ["on": on], timeout: Self.modelTimeout)
  }

  public func changeOutsideAi(_ on: Bool) async throws -> Bool {
    try await write("PUT", "/api/account/outside_ai", json: OutsideAiSettings(on: on), as: OutsideAiSettings.self).on
  }

  // MARK: - Agents (administrators)

  public func agents() async throws -> [Agent] { try await get("/api/account/agents", as: Agents.self).agents }
  public func agent(_ agent: UserID) async throws -> AgentSettings { try await get("/api/account/agents/\(id(agent))", as: AgentAnswer.self).agent }

  public func createAgent(_ agent: AgentChanges, avatar: ChosenPhoto? = nil) async throws -> AgentSettings {
    let (data, _) = try await send(timed(userRequest("POST", "/api/account/agents", agent, photo: avatar)))
    return try decode(data, from: "/api/account/agents", as: AgentAnswer.self).agent
  }

  public func changeAgent(_ agent: UserID, _ changes: AgentChanges, avatar: ChosenPhoto? = nil) async throws -> AgentSettings {
    let path = "/api/account/agents/\(id(agent))"
    let (data, _) = try await send(timed(userRequest("PATCH", path, changes, photo: avatar)))
    return try decode(data, from: path, as: AgentAnswer.self).agent
  }

  public func removeAgentAvatar(_ agent: UserID) async throws -> AgentSettings {
    try await write("DELETE", "/api/account/agents/\(id(agent))/avatar", as: AgentAnswer.self).agent
  }

  public func deleteAgent(_ agent: UserID) async throws { try await perform("DELETE", "/api/account/agents/\(id(agent))") }

  /** Tries an agent's setup with a question; nil `agent` for one not yet saved. */
  public func tryAgent(_ trial: AgentTrial, agent: UserID?) async throws -> AgentTrialAnswer {
    let path = agent.map { "/api/account/agents/\(id($0))/trials" } ?? "/api/account/agents/trials"
    return try await write("POST", path, json: trial, timeout: Self.modelTimeout)
  }

  public func agentTools(_ agent: UserID) async throws -> [OfferedApp] { try await get("/api/account/agents/\(id(agent))/tools", as: AgentTools.self).apps }

  public func pickAgentTools(_ agent: UserID, _ tools: [ToolPick]) async throws -> [OfferedApp] {
    try await write("PUT", "/api/account/agents/\(id(agent))/tools", json: AgentToolPicks(tools: tools), as: AgentTools.self).apps
  }

  private func timed(_ request: URLRequest) -> URLRequest {
    var request = request
    request.timeoutInterval = Self.modelTimeout
    return request
  }

  // MARK: - Connected apps (administrators)

  public func apps() async throws -> [AppSummary] { try await get("/api/account/apps", as: Apps.self).apps }
  public func app(_ app: AppID) async throws -> App { try await get("/api/account/apps/\(id(app))", as: AppAnswer.self).app }
  public func connectApp(_ app: AppChanges) async throws -> App { try await write("POST", "/api/account/apps", json: app, as: AppAnswer.self).app }
  public func changeApp(_ app: AppID, _ changes: AppChanges) async throws -> App { try await write("PATCH", "/api/account/apps/\(id(app))", json: changes, as: AppAnswer.self).app }
  public func readAppTools(_ app: AppID) async throws -> App { try await write("POST", "/api/account/apps/\(id(app))/tools", as: AppAnswer.self).app }
  /** Removes an app. An app Ember wasn't signed in to answers 204 with no body (`Partial<AppRemoved>`). */
  public func disconnectApp(_ app: AppID) async throws -> AppRemoved {
    let path = "/api/account/apps/\(id(app))"
    let (data, _) = try await send(request(path, method: "DELETE"))
    guard !data.isEmpty else { return AppRemoved(revoked: nil) }
    return try decode(data, from: path)
  }

  /** Starts signing in to a new app's server: the address to sign in at. */
  public func beginNewAppSignIn(_ app: AppClient) async throws -> String {
    try await write("POST", "/api/account/app-sign-ins", json: app, as: AppSignInBegun.self).authorizationUrl
  }

  public func beginAppSignIn(_ app: AppID, client: AppClient? = nil) async throws -> String {
    let path = "/api/account/apps/\(id(app))/sign-in"
    guard let client else { return try await write("POST", path, as: AppSignInBegun.self).authorizationUrl }
    return try await write("POST", path, json: client, as: AppSignInBegun.self).authorizationUrl
  }

  public func finishAppSignIn(_ back: AppSignInReturn) async throws -> AppSignInFinished {
    try await write("POST", "/api/account/app-sign-ins/finish", json: back)
  }

  // MARK: - Outside AI (the consent page)

  public func describeOutsideAsk(_ ask: OutsideAsk) async throws -> OutsideAsked { try await write("POST", "/api/outside/asks", json: ask) }

  /** Answers an AI app's request: where to send the browser back to. */
  public func answerOutsideAsk(_ answer: OutsideAnswer) async throws -> String {
    try await write("POST", "/api/outside/answers", json: answer, as: OutsideAnswered.self).redirectTo
  }

  // MARK: - Chat bots (administrators)

  public func bots() async throws -> [Bot] { try await get("/api/account/bots", as: Bots.self).bots }
  public func bot(_ bot: UserID) async throws -> BotSettings { try await get("/api/account/bots/\(id(bot))", as: BotAnswer.self).bot }

  public func createBot(_ bot: BotChanges, avatar: ChosenPhoto? = nil) async throws {
    try await send(userRequest("POST", "/api/account/bots", bot, photo: avatar))
  }

  public func changeBot(_ bot: UserID, _ changes: BotChanges, avatar: ChosenPhoto? = nil) async throws {
    try await send(userRequest("PATCH", "/api/account/bots/\(id(bot))", changes, photo: avatar))
  }

  public func deleteBot(_ bot: UserID) async throws { try await perform("DELETE", "/api/account/bots/\(id(bot))") }
  public func resetBotKey(_ bot: UserID) async throws { try await perform("PUT", "/api/account/bots/\(id(bot))/key") }

  // MARK: - Helpers

  func decode<T: Decodable>(_ data: Data, from path: String, as type: T.Type) throws -> T { try decode(data, from: path) }
}
