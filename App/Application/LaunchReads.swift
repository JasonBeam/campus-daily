import Core

/// What the live app reads when the user launches it (the scene's launch `.task`), in order.
@MainActor enum LaunchReads {
    static func run(campus: CampusModel, laundry: LaundryModel) async {
        // A previous person's snapshot left under the stale mark is replaced first, offline.
        await campus.finishPendingClear()
        await campus.dropCampusWideMeter()
        campus.matchPowerAutomatically(.launch)
        await campus.refresh()
        await laundry.refresh()
        await laundry.readOrderAtLaunch()
    }
}
