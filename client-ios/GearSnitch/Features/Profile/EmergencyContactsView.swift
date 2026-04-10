import SwiftUI

// MARK: - Emergency Contact

struct EmergencyContact: Identifiable {
    let id = UUID()
    var name: String
    var phone: String
    var email: String
    var notifyOnAlert: Bool
}

struct EmergencyContactView: View {
    @State private var contacts: [EmergencyContact] = []
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newPhone = ""
    @State private var newEmail = ""
    @State private var newNotify = true

    var body: some View {
        List {
            if contacts.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 36))
                            .foregroundColor(.gsTextSecondary)

                        Text("No emergency contacts")
                            .font(.subheadline)
                            .foregroundColor(.gsTextSecondary)

                        Text("Add contacts who should be notified during alerts.")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.gsSurface)
            } else {
                ForEach(contacts) { contact in
                    contactRow(contact)
                        .listRowBackground(Color.gsSurface)
                }
                .onDelete(perform: deleteContact)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Emergency Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.gsEmerald)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addContactSheet
        }
    }

    private func contactRow(_ contact: EmergencyContact) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(contact.name)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)

            HStack(spacing: 16) {
                Label(contact.phone, systemImage: "phone")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)

                if !contact.email.isEmpty {
                    Label(contact.email, systemImage: "envelope")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
            }

            if contact.notifyOnAlert {
                Label("Notified on alerts", systemImage: "bell.fill")
                    .font(.caption2)
                    .foregroundColor(.gsEmerald)
            }
        }
        .padding(.vertical, 4)
    }

    private func deleteContact(at offsets: IndexSet) {
        contacts.remove(atOffsets: offsets)
    }

    // MARK: - Add Sheet

    private var addContactSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $newName)
                    TextField("Phone", text: $newPhone)
                        .keyboardType(.phonePad)
                    TextField("Email (optional)", text: $newEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Contact Info")
                }
                .listRowBackground(Color.gsSurface)
                .foregroundColor(.gsText)

                Section {
                    Toggle(isOn: $newNotify) {
                        Text("Notify on device alerts")
                            .foregroundColor(.gsText)
                    }
                    .tint(.gsEmerald)
                }
                .listRowBackground(Color.gsSurface)

                Section {
                    Button {
                        addContact()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Add Contact")
                                .font(.headline)
                            Spacer()
                        }
                        .foregroundColor(.black)
                    }
                    .listRowBackground(Color.gsEmerald)
                    .disabled(newName.isEmpty || newPhone.isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.gsBackground.ignoresSafeArea())
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addContact() {
        let contact = EmergencyContact(
            name: newName,
            phone: newPhone,
            email: newEmail,
            notifyOnAlert: newNotify
        )
        contacts.append(contact)
        newName = ""
        newPhone = ""
        newEmail = ""
        newNotify = true
        showAddSheet = false
    }
}

// Typealias for navigation reference
typealias EmergencyContactsView = EmergencyContactView

#Preview {
    NavigationStack {
        EmergencyContactsView()
    }
    .preferredColorScheme(.dark)
}
