import ADBKit
import Testing

/// The id contract between `FeatureRegistry`/`FeatureEngine` and
/// `FeatureDetailView`'s pane routing. Both omissions this covers used to fail
/// silently: an implemented view feature with no route opens to "Coming Soon",
/// and a route left behind by a renamed feature is a branch nothing can reach.
/// (`implementedIDsAreAllRealFeatures` in ADBKit only pairs the engine with the
/// registry — it never sees the App layer's routing.)
@Suite struct FeatureDetailRouteTests {
    private let routedIDs = Set(FeatureDetailRoute.allCases.map(\.rawValue))
    private let paneKinds: Set<FeatureKind> = [.view, .system]

    /// Step 3 of the "Adding a feature" checklist: a `.view`/`.system` feature
    /// the engine calls implemented must have a pane, or the screen it opens is
    /// `ComingSoonView` while search, the sidebar, and its hotkey all offer it.
    @Test func everyImplementedViewFeatureHasARoute() {
        for feature in FeatureRegistry.all
        where paneKinds.contains(feature.kind)
            && FeatureEngine.implementedIDs.contains(feature.id) {
            #expect(
                routedIDs.contains(feature.id),
                """
                \(feature.id) is \(feature.kind.rawValue)-kind and implemented but has no \
                FeatureDetailRoute case — it would open to "Coming Soon"
                """)
        }
    }

    /// The other direction: a route must name a real view feature. A renamed or
    /// deleted feature leaves its case here pointing at nothing, and the pane
    /// becomes dead code no id can reach.
    @Test func everyRouteMapsToAViewFeature() {
        for route in FeatureDetailRoute.allCases {
            guard let feature = FeatureRegistry.byID[route.rawValue] else {
                Issue.record(
                    """
                    FeatureDetailRoute routes '\(route.rawValue)', which is not \
                    a feature in the registry — its pane is unreachable
                    """)
                continue
            }
            #expect(
                paneKinds.contains(feature.kind),
                """
                FeatureDetailRoute routes '\(route.rawValue)', which is \
                \(feature.kind.rawValue)-kind — detailByKind only reaches routes \
                for view features
                """)
        }
    }
}
