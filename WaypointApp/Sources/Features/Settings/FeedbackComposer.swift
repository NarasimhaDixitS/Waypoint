import SwiftUI
import MessageUI

/// Feedback, sent from the person's own mail account.
///
/// **Why not a form that posts somewhere.** A send-an-email service wants an API key, and an
/// app cannot hold one: anyone can read the strings out of a shipped `.ipa` — this project has
/// done exactly that all week — and a mail-provider key lets whoever finds it send mail as the
/// domain that owns it. The honest version of that design needs a server in front of it, which
/// is a backend, which this app deliberately doesn't have.
///
/// It would also cost the one claim Waypoint can currently make without qualification. The
/// privacy manifest declares no collection and the App Store label reads "Data Not Collected";
/// a form with a mandatory email field collects contact information, and that has to be
/// declared. Handing the draft to Mail collects nothing — the message never passes through
/// anything of ours, and the reply address is the account it was sent from, which is the
/// mandatory-email requirement satisfied by construction rather than by a text field.
///
/// The cost is real and worth stating: it only works on a device with Mail set up, and the
/// person has to press send themselves. `canSend` answers the first, and the caller shows the
/// address plainly when the answer is no.
enum Feedback {
    static let address = "sn.dixitdixit@gmail.com"

    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    static var subject: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Waypoint feedback — \(version) (\(build))"
    }

    /// Prefilled below a blank space for the actual message.
    ///
    /// Only what helps answer a bug report: the build, the OS, the device model and which
    /// palette is on, because half the visual bugs found this week were palette-specific.
    /// Nothing about the person, and nothing about their tasks — that all stays on the device
    /// whatever this screen is for.
    static var body: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let palette = Palette.current == .paper ? "Paper" : "Standard"
        return """


        —
        Waypoint \(version) (\(build)) · iOS \(UIDevice.current.systemVersion) · \(deviceModel()) · \(palette)
        """
    }

    /// "iPhone16,2" rather than the marketing name. A lookup table of marketing names goes
    /// stale every September; the identifier is exact and searchable.
    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

/// Wraps `MFMailComposeViewController`, which has no SwiftUI equivalent.
struct MailComposer: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([Feedback.address])
        controller.setSubject(Feedback.subject)
        controller.setMessageBody(Feedback.body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            // Dismissed the same way whether it was sent, saved or cancelled. Reporting "sent"
            // here would be a guess: the result says the composer handed the message to Mail,
            // not that it left the device.
            controller.dismiss(animated: true) { [onFinish] in onFinish() }
        }
    }
}
