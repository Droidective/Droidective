import Foundation

/// Pure operations over a collection's `[ApiItem]` tree. Every function returns
/// a new tree rather than mutating in place, so the view can apply an edit and
/// persist the result without worrying about partially-applied state.
public enum ApiCollectionTree: Sendable {

    // MARK: - Lookup

    /// The item with `id`, searched depth-first through folders.
    public static func find(_ id: String, in items: [ApiItem]) -> ApiItem? {
        for item in items {
            if item.id == id { return item }
            if case .folder(let folder) = item, let hit = find(id, in: folder.items) { return hit }
        }
        return nil
    }

    public static func findRequest(_ id: String, in items: [ApiItem]) -> SavedRequest? {
        find(id, in: items)?.asRequest
    }

    /// Folder names from the root down to `id`, excluding the item itself.
    /// `[]` means the item sits at the top level; nil means it isn't in the tree
    /// — the two need to be distinguishable for breadcrumbs.
    public static func path(to id: String, in items: [ApiItem]) -> [String]? {
        for item in items {
            if item.id == id { return [] }
            guard case .folder(let folder) = item else { continue }
            if let deeper = path(to: id, in: folder.items) { return [folder.name] + deeper }
        }
        return nil
    }

    /// Every request in the tree, depth-first, in display order.
    public static func allRequests(in items: [ApiItem]) -> [SavedRequest] {
        var out: [SavedRequest] = []
        for item in items {
            switch item {
            case .request(let request): out.append(request)
            case .folder(let folder): out.append(contentsOf: allRequests(in: folder.items))
            }
        }
        return out
    }

    public static func requestCount(in items: [ApiItem]) -> Int { allRequests(in: items).count }

    // MARK: - Mutation

    /// Replaces the request carrying `request.id`. Returns nil when the id
    /// isn't in the tree, so callers can fall back to inserting.
    public static func replacing(_ request: SavedRequest, in items: [ApiItem]) -> [ApiItem]? {
        var changed = false
        var out: [ApiItem] = []
        out.reserveCapacity(items.count)
        for item in items {
            switch item {
            case .request(let existing) where existing.id == request.id:
                out.append(.request(request))
                changed = true
            case .folder(var folder):
                if let updated = replacing(request, in: folder.items) {
                    folder.items = updated
                    changed = true
                }
                out.append(.folder(folder))
            default:
                out.append(item)
            }
        }
        return changed ? out : nil
    }

    /// Replaces a folder's name/note in place, keeping its children.
    public static func renamingFolder(
        _ folderId: String, to name: String, in items: [ApiItem]
    ) -> [ApiItem] {
        items.map { item in
            guard case .folder(var folder) = item else { return item }
            if folder.id == folderId {
                folder.name = name
            } else {
                folder.items = renamingFolder(folderId, to: name, in: folder.items)
            }
            return .folder(folder)
        }
    }

    /// Removes the item with `id` wherever it sits.
    public static func removing(_ id: String, from items: [ApiItem]) -> [ApiItem] {
        items.compactMap { item in
            if item.id == id { return nil }
            guard case .folder(var folder) = item else { return item }
            folder.items = removing(id, from: folder.items)
            return .folder(folder)
        }
    }

    /// Appends `new` inside `folderId`, or at the top level when it is nil.
    /// Returns the tree unchanged if the folder doesn't exist.
    public static func appending(
        _ new: ApiItem, toFolder folderId: String?, in items: [ApiItem]
    ) -> [ApiItem] {
        guard let folderId else { return items + [new] }
        var found = false
        let result = insert(new, into: folderId, in: items, found: &found)
        return found ? result : items
    }

    private static func insert(
        _ new: ApiItem, into folderId: String, in items: [ApiItem], found: inout Bool
    ) -> [ApiItem] {
        items.map { item in
            guard case .folder(var folder) = item else { return item }
            if folder.id == folderId {
                folder.items.append(new)
                found = true
            } else {
                folder.items = insert(new, into: folderId, in: folder.items, found: &found)
            }
            return .folder(folder)
        }
    }

    /// Moves `id` into `folderId` (nil = top level). A folder cannot be moved
    /// into itself or one of its own descendants — that would detach the
    /// subtree from the tree entirely.
    public static func moving(
        _ id: String, toFolder folderId: String?, in items: [ApiItem]
    ) -> [ApiItem] {
        guard let moved = find(id, in: items) else { return items }
        if let folderId {
            if folderId == id { return items }
            if case .folder(let folder) = moved, find(folderId, in: folder.items) != nil {
                return items
            }
        }
        let pruned = removing(id, from: items)
        return appending(moved, toFolder: folderId, in: pruned)
    }

    /// Deep-copies an item with fresh ids so a duplicate never shares identity
    /// with its source (which would make both sides of the tree edit together).
    public static func duplicating(_ item: ApiItem, nameSuffix: String = " Copy") -> ApiItem {
        switch item {
        case .request(var request):
            let now = Date().timeIntervalSince1970
            request.id = UUID().uuidString
            request.name += nameSuffix
            request.createdAt = now
            request.modifiedAt = now
            return .request(request)
        case .folder(var folder):
            folder.id = UUID().uuidString
            folder.name += nameSuffix
            folder.items = folder.items.map { duplicating($0, nameSuffix: "") }
            return .folder(folder)
        }
    }

    /// Fresh ids throughout, with names untouched. Used on import so two
    /// imports of the same file don't collide.
    public static func reidentifying(_ items: [ApiItem]) -> [ApiItem] {
        items.map { item in
            switch item {
            case .request(var request):
                request.id = UUID().uuidString
                request.headers = reidentify(request.headers)
                request.queryParams = reidentify(request.queryParams)
                request.pathVariables = reidentify(request.pathVariables)
                request.body.formFields = reidentify(request.body.formFields)
                return .request(request)
            case .folder(var folder):
                folder.id = UUID().uuidString
                folder.items = reidentifying(folder.items)
                return .folder(folder)
            }
        }
    }

    private static func reidentify(_ pairs: [ApiKeyValue]) -> [ApiKeyValue] {
        pairs.map { pair in
            var copy = pair
            copy.id = UUID().uuidString
            return copy
        }
    }

    // MARK: - Search

    /// Items whose name, URL, or method matches `query`, flattened with the
    /// folder path that leads to each one. An empty query matches nothing —
    /// the caller shows the normal tree instead.
    public static func search(_ query: String, in items: [ApiItem]) -> [(path: [String], request: SavedRequest)] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        var out: [(path: [String], request: SavedRequest)] = []
        walk(items, prefix: []) { path, request in
            let haystack = "\(request.name) \(request.url) \(request.method.rawValue)".lowercased()
            if haystack.contains(needle) { out.append((path: path, request: request)) }
        }
        return out
    }

    private static func walk(
        _ items: [ApiItem], prefix: [String], visit: ([String], SavedRequest) -> Void
    ) {
        for item in items {
            switch item {
            case .request(let request): visit(prefix, request)
            case .folder(let folder): walk(folder.items, prefix: prefix + [folder.name], visit: visit)
            }
        }
    }

    /// Secret-free deep copy, for export.
    public static func withoutSecrets(_ items: [ApiItem]) -> [ApiItem] {
        items.map { item in
            switch item {
            case .request(let request): return .request(request.withoutSecrets())
            case .folder(var folder):
                folder.items = withoutSecrets(folder.items)
                return .folder(folder)
            }
        }
    }
}
