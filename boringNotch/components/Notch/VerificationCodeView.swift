//
//  VerificationCodeView.swift
//  boringNotch
//
//  Left half of the open notch while a verification email is showing.
//  Mirrors MusicPlayerView's geometry so the calendar on the right doesn't move.
//

import Defaults
import SwiftUI

struct VerificationCodeView: View {
    let alert: VerificationAlert
    @ObservedObject private var manager = VerificationMailManager.shared
    @State private var copied = false
    @State private var appeared = false

    private let glow = Color(red: 0.55, green: 0.78, blue: 1.0)
    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)

    var body: some View {
        HStack {
            logoTile.padding(.all, 5)
            details
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.94, anchor: .leading)
        .onAppear { withAnimation(spring) { appeared = true } }
        .onChange(of: alert.id) { copied = false }
    }

    private var cornerRadius: CGFloat {
        Defaults[.cornerRadiusScaling]
            ? MusicPlayerImageSizes.cornerRadiusInset.opened
            : MusicPlayerImageSizes.cornerRadiusInset.closed
    }

    private var logoTile: some View {
        ZStack {
            Circle()
                .fill(glow)
                .scaleEffect(1.25)
                .blur(radius: 34)
                .opacity(appeared ? 0.55 : 0)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white)
                .overlay(
                    Image("gmail")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(18)
                )
                .shadow(color: glow.opacity(0.35), radius: 8)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Gmail")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: isCode ? 26 : 18, weight: .bold, design: isCode ? .monospaced : .default))
                    .tracking(isCode ? 2 : 0)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .textSelection(.enabled)
                Text(alert.sender)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.top, 10)
            .padding(.leading, 5)
            .padding(.trailing, 22)

            Spacer(minLength: 8)

            actionButton
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)
        }
    }

    private var isCode: Bool {
        if case .code = alert.payload { return true }
        return false
    }

    private var headline: String {
        switch alert.payload {
        case .code(let code): return code
        case .magicLink: return "Sign-in link"
        }
    }

    private var actionButton: some View {
        Button {
            switch alert.payload {
            case .code:
                manager.copyCurrentCode()
                withAnimation(spring) { copied = true }
            case .magicLink:
                manager.openCurrentLink()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: buttonIcon)
                    .contentTransition(.symbolEffect(.replace))
                Text(buttonTitle)
                    .contentTransition(.interpolate)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .frame(height: 30)
            .background(Capsule().fill(Color.white))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var buttonTitle: String {
        switch alert.payload {
        case .code: return copied ? "Copied" : "Copy Code"
        case .magicLink: return "Open Link"
        }
    }

    private var buttonIcon: String {
        switch alert.payload {
        case .code: return copied ? "checkmark" : "doc.on.doc"
        case .magicLink: return "safari"
        }
    }

    private var closeButton: some View {
        Button {
            manager.dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.top, 6)
        .accessibilityLabel("Dismiss")
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
