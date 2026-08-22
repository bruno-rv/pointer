import PointerAppKit

MainActor.assumeIsolated {
    let application = PointerApplication.shared as! PointerApplication
    let controller = PointerApplicationController()
    application.commandRouter = controller.commandRouter
    application.delegate = controller
    application.setActivationPolicy(.accessory)
    application.run()
}
