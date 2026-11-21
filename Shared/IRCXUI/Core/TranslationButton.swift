import AppCoreUI
import EmberKit
import SwiftUI

/**
 * The translation button beside a field (web translation-button.tsx): it opens what the field asks for in
 * seven languages, each after its country's flag. Hidden while the workspace hides translation buttons
 * (`Account.hideTranslationButtons`), as it does until an administrator shows them.
 */
struct TranslationButton: View {
  /** A `Translations` key, such as `email_address`. */
  let key: String
  let account: Account?
  var classic = false
  @State private var open = false
  @Environment(\.theme) private var theme

  var body: some View {
    if let account, !account.hideTranslationButtons, let translations = Translations.of(key) {
      button
        .popover(isPresented: $open) {
          Grid(alignment: .leading, horizontalSpacing: Spacing.md, verticalSpacing: Spacing.sm) {
            ForEach(Array(translations.enumerated()), id: \.offset) { _, translation in
              GridRow {
                Text(translation.flag)
                Text(translation.text).fixedSize(horizontal: false, vertical: true)
              }
            }
          }
          .font(classic ? Theme.font(12) : DesignFont.body)
          .foregroundStyle(classic ? theme.text : Color.primary)
          .padding(Spacing.xl)
          .frame(maxWidth: 360)
          .background(classic ? theme.sidebar : Color.clear)
          .presentationCompactAdaptation(.popover)
        }
    }
  }

  @ViewBuilder private var button: some View {
    if classic {
      Button("[tr]") { open.toggle() }
        .buttonStyle(.plain)
        .foregroundStyle(theme.link)
        .font(Theme.font(12))
        .help("Translate")
    } else {
      PaneIconButton(systemImage: "translate", help: "Translate") { open.toggle() }
    }
  }
}
