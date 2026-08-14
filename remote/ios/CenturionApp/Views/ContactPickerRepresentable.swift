import ContactsUI
import SwiftUI

/// System contact picker — fills name, email, and phone for Family Beneficiary referrals.
/// Uses `CNContactPickerViewController` so the user chooses one contact without bulk Contacts access.
struct ContactPickerRepresentable: UIViewControllerRepresentable {
    var onPick: (_ name: String, _ email: String, _ phone: String) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactEmailAddressesKey,
            CNContactPhoneNumbersKey,
        ]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (_ name: String, _ email: String, _ phone: String) -> Void
        let onCancel: () -> Void

        init(
            onPick: @escaping (_ name: String, _ email: String, _ phone: String) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let formatter = CNContactFormatter()
            formatter.style = .fullName
            let name = formatter.string(from: contact)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let email = (contact.emailAddresses.first?.value as String?)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let phone = contact.phoneNumbers.first?.value.stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            onPick(name, email, phone)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
