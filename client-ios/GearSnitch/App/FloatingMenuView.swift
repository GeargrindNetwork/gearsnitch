import SwiftUI

// MARK: - Menu Item

struct FloatingMenuItem: Identifiable {
    let id: String
    let icon: String
    let label: String
    let color: Color
    let tab: Tab?
    let action: (() -> Void)?

    init(tab: Tab, icon: String, label: String, color: Color = .gsText) {
        self.id = tab.rawValue
        self.icon = icon
        self.label = label
        self.color = color
        self.tab = tab
        self.action = nil
    }

    init(id: String, icon: String, label: String, color: Color = .gsText, action: @escaping () -> Void) {
        self.id = id
        self.icon = icon
        self.label = label
        self.color = color
        self.tab = nil
        self.action = action
    }
}

// MARK: - Floating Menu

struct FloatingMenuView: View {
    @Binding var selectedTab: Tab
    @Binding var isExpanded: Bool
    let onHospitals: () -> Void
    let onLabs: () -> Void

    private let menuItems: [FloatingMenuItem] = [
        FloatingMenuItem(tab: .dashboard, icon: "house.fill", label: "Dashboard"),
        FloatingMenuItem(tab: .workouts, icon: "figure.run", label: "Workouts"),
        FloatingMenuItem(tab: .health, icon: "heart.text.clipboard", label: "Health"),
        FloatingMenuItem(tab: .store, icon: "bag.fill", label: "Store"),
        FloatingMenuItem(tab: .profile, icon: "person.crop.circle.fill", label: "Profile"),
    ]

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Spacer()

            // Expanded menu items
            if isExpanded {
                VStack(alignment: .trailing, spacing: 6) {
                    // Special items at top
                    menuButton(
                        icon: "cross.case.fill",
                        label: "Hospitals",
                        color: .gsDanger,
                        isSelected: false
                    ) {
                        onHospitals()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isExpanded = false
                        }
                    }

                    menuButton(
                        icon: "staroflife.fill",
                        label: "Labs",
                        color: .gsCyan,
                        isSelected: false
                    ) {
                        onLabs()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isExpanded = false
                        }
                    }

                    Divider()
                        .frame(width: 160)
                        .background(Color.gsBorder)
                        .padding(.vertical, 4)

                    // Tab items
                    ForEach(menuItems) { item in
                        menuButton(
                            icon: item.icon,
                            label: item.label,
                            color: item.color,
                            isSelected: item.tab == selectedTab
                        ) {
                            if let tab = item.tab {
                                selectedTab = tab
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isExpanded = false
                            }
                        }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity),
                    removal: .scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity)
                ))
                .padding(.bottom, 8)
            }

            // Hamburger button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.gsEmerald, Color.gsEmerald.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.gsEmerald.opacity(0.4), radius: 12, y: 4)

                    Image(systemName: isExpanded ? "xmark" : "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.black)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3), value: isExpanded)
                }
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Menu Button

    private func menuButton(icon: String, label: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .gsEmerald : .gsText)

                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(isSelected ? .gsEmerald : color)
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.gsEmerald.opacity(0.1) : Color.clear)
            .cornerRadius(10)
        }
    }
}

#Preview {
    ZStack {
        Color.gsBackground.ignoresSafeArea()
        FloatingMenuView(
            selectedTab: .constant(.dashboard),
            isExpanded: .constant(true),
            onHospitals: {},
            onLabs: {}
        )
    }
    .preferredColorScheme(.dark)
}
