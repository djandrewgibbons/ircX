import EmberKit
import Foundation
import Observation

/**
 * An instance's message search (web `SearchBox` and `SearchPage`): the search shown, its results page by
 * page, and the recent searches.
 */
@MainActor
@Observable
public final class SearchModel {
  /** The search the results are for. */
  public private(set) var search = Search(q: "")
  public private(set) var sort = SearchSort.newest
  public private(set) var matches: [SearchMatch] = []
  /** The cursor for the next page, nil after the last. */
  public private(set) var next: Int?
  /** The rooms the matches are in, for their names and icons. */
  public private(set) var rooms: [RoomID: Room] = [:]
  public private(set) var recent: [Search] = []
  public private(set) var busy = false
  public private(set) var loadingMore = false
  /** Why the last search failed, which clears the results. */
  public private(set) var error: String?
  /** Whether a search has been run since the instance connected. */
  public private(set) var ran = false

  /** Runs `search` (`POST /api/searches`, which records it as the newest recent search). */
  func run(_ search: Search, sort: SearchSort, record: Bool, api: EmberAPI) async {
    guard search.isSearchable else { return }
    guard search.q.count <= Searches.maxSearchLength else {
      error = Searches.searchTooLong
      return
    }
    self.search = search
    self.sort = sort
    busy = true
    error = nil
    ran = true
    defer { busy = false }
    do {
      let results = record ? try await api.recordSearch(search, sort: sort) : try await api.search(search, sort: sort)
      adopt(results, appending: false)
    } catch {
      logger.error("Searching failed: \(error.localizedDescription, privacy: .public)")
      matches = []
      next = nil
      self.error = error.localizedDescription
    }
  }

  /** Show more: the next page, without the matches already shown (`withNextPage`). */
  func more(api: EmberAPI) async {
    guard let next, !loadingMore else { return }
    loadingMore = true
    defer { loadingMore = false }
    do {
      adopt(try await api.search(search, sort: sort, cursor: next), appending: true)
    } catch {
      logger.error("Loading more results failed: \(error.localizedDescription, privacy: .public)")
      self.error = error.localizedDescription
    }
  }

  /** Loads the recent searches, as the box does when it opens (`GET /api/searches?q=`). */
  func loadRecent(api: EmberAPI) async {
    do {
      recent = try await api.search(Search(q: "")).recent
    } catch {
      logger.error("Loading recent searches failed: \(error.localizedDescription, privacy: .public)")
      self.error = error.localizedDescription
    }
  }

  func clearRecent(api: EmberAPI) async throws {
    try await api.clearSearches()
    recent = []
  }

  /** Sets what a search answered, for render tests, which draw screens without a server. */
  func showForRendering(_ search: Search, _ results: SearchResults) {
    self.search = search
    ran = true
    adopt(results, appending: false)
  }

  private func adopt(_ results: SearchResults, appending: Bool) {
    if appending {
      let shown = Set(matches.map(\.message.id))
      matches += results.matches.filter { !shown.contains($0.message.id) }
    } else {
      matches = results.matches
    }
    next = results.next
    for room in results.rooms { rooms[room.id] = room }
    recent = results.recent
  }

  /** What the results page's heading says (`countLabel`). */
  public var countLabel: String { NavigationText.resultCount(matches.count, more: next != nil) }
}

extension InstanceSession {
  /** Runs a search and shows its results page. */
  public func runSearch(_ search: Search, sort: SearchSort = .newest, record: Bool = true) {
    show(.search(search, sort))
    Task { await self.search.run(search, sort: sort, record: record, api: api) }
  }

  /** A typed search, its modifiers made filters, `in:` naming a room and `from:` a person by name. */
  public func typedSearch(_ text: String, in room: RoomID? = nil) -> (search: Search, sort: SearchSort?) {
    guard let me else { return (Search(q: text, in: room), nil) }
    var (search, sort) = Searches.withTypedFilters(
      Search(q: text, in: room), me: me.id, room: { self.room(named: InputCommand.roomName($0) ?? $0)?.id },
      person: { self.person(named: $0)?.id })
    if search.in == nil { search.in = room }
    return (search, sort)
  }

  public func moreResults() { Task { await search.more(api: api) } }
  public func loadRecentSearches() { Task { await search.loadRecent(api: api) } }
  public func clearRecentSearches() async throws { try await search.clearRecent(api: api) }

  /** Opens a result in its room, at the message, or its thread for a reply (`permalinkOf`). */
  public func open(_ match: SearchMatch) {
    let message = match.message
    show(message.roomId, messageId: message.parentId == nil ? message.id : nil, threadId: message.parentId)
  }

  /** What a result's card names its room: the room, a DM's people, or that it's one they've left. */
  public func roomName(of match: SearchMatch) -> String {
    if let listed = rooms.first(where: { $0.id == match.message.roomId }) { return title(of: listed.room) }
    if let room = search.rooms[match.message.roomId] { return title(of: room) }
    return "A room you've left"
  }
}
