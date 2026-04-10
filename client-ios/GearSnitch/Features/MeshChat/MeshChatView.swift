import SwiftUI

struct MeshChatView: View {
    @StateObject private var viewModel = MeshChatViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            chatHeader

            Divider().background(Color.gsBorder)

            // Messages
            messageList

            Divider().background(Color.gsBorder)

            // Input bar
            messageInputBar
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Mesh Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.startChat()
        }
        .onDisappear {
            viewModel.stopChat()
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: 12) {
            // Signal indicator
            ZStack {
                Circle()
                    .fill(viewModel.isConnected ? Color.gsEmerald.opacity(0.2) : Color.gsDanger.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(viewModel.isConnected ? .gsEmerald : .gsDanger)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.gymName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.gsEmerald)
                        .frame(width: 6, height: 6)

                    Text("\(viewModel.nearbyUsers) user\(viewModel.nearbyUsers == 1 ? "" : "s") nearby")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
            }

            Spacer()

            Text(viewModel.anonymousName)
                .font(.caption)
                .foregroundColor(.gsEmerald)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.gsEmerald.opacity(0.12))
                .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.gsSurface)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        if message.senderId == "system" {
                            systemMessageBubble(message)
                        } else {
                            chatBubble(message)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isOutgoing { Spacer(minLength: 48) }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
                if !message.isOutgoing {
                    Text(message.senderName)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.gsEmerald)
                }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(.gsText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.isOutgoing
                            ? Color.gsEmerald
                            : Color(red: 63 / 255, green: 63 / 255, blue: 70 / 255) // zinc-700
                    )
                    .cornerRadius(16)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gsTextSecondary)
            }
            .id(message.id)

            if !message.isOutgoing { Spacer(minLength: 48) }
        }
    }

    private func systemMessageBubble(_ message: ChatMessage) -> some View {
        Text(message.text)
            .font(.caption2)
            .foregroundColor(.gsTextSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gsSurfaceRaised)
            .cornerRadius(10)
            .frame(maxWidth: .infinity)
            .id(message.id)
    }

    // MARK: - Input Bar

    private var messageInputBar: some View {
        HStack(spacing: 10) {
            TextField("Message...", text: $viewModel.messageText, axis: .vertical)
                .font(.subheadline)
                .foregroundColor(.gsText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.gsSurfaceRaised)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gsBorder, lineWidth: 1)
                )
                .lineLimit(1...4)
                .focused($isInputFocused)

            Button {
                viewModel.sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(
                        viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? .gsTextSecondary
                            : .gsEmerald
                    )
            }
            .disabled(viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gsSurface)
    }
}

#Preview {
    NavigationStack {
        MeshChatView()
    }
    .preferredColorScheme(.dark)
}
