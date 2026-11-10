import Core

/// What the live app reads when the user launches it (the scene's launch `.task`), in order.
@MainActor enum LaunchReads {
    static func run(campus: CampusModel, laundry: LaundryModel) async {
        await campus.dropCampusWideMeter()
        campus.matchPowerAutomatically(.launch)
        await campus.refresh()
        await laundry.refresh()
        await laundry.readOrderAtLaunch()
    }
}
