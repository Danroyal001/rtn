// The pieces every MyRTN screen is built from. Each control has a tooltip and
// a name a screen reader announces; each heading is a heading.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../styles/theme.dart';

/// The page's own heading, level 1, with a line under it.
@DVFunctionalWidget()
Widget _pageTitle(BuildContext context, String title, {String subtitle = ''}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  return DVBox.list(<Widget>[
    DVText(title).modifier(const DVModifier().fontSize(26).fontWeight(FontWeight.w800).semanticHeading(1)),
    if (subtitle.isNotEmpty) DVText(subtitle).modifier(const DVModifier().color(colors.onSurfaceVariant).fontSize(15)),
  ], spacing: 4);
}

/// A section heading, level 2.
@DVFunctionalWidget()
Widget _sectionTitle(BuildContext context, String title, {String hint = ''}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  return DVBox.list(
    <Widget>[
      DVText(title).modifier(const DVModifier().fontSize(18).fontWeight(FontWeight.w700).semanticHeading(2)),
      if (hint.isNotEmpty) DVText(hint).modifier(const DVModifier().color(colors.onSurfaceVariant).fontSize(13)),
    ],
    spacing: 2,
    modifier: const DVModifier().paddingOnly(top: 8),
  );
}

/// A card.
@DVFunctionalWidget()
Widget _panel(BuildContext context, List<Widget> children, {double spacing = 12, bool accent = false}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return DVBox.list(
    children,
    spacing: spacing,
    modifier: const DVModifier()
        .padding(16)
        .rounded(16)
        .backgroundColor(accent ? colors.primaryContainer : (dark ? const Color(0xFF151D1D) : Colors.white))
        .border(Border.all(color: colors.outlineVariant.withValues(alpha: 0.6))),
  );
}

/// A button. [tooltip] says what pressing it does; with no [onPressed] it is
/// shown, named, and does nothing.
@DVFunctionalWidget()
Widget _actionButton(
  BuildContext context,
  String label, {
  required String tooltip,
  VoidCallback? onPressed,
  bool primary = true,
  bool busy = false,
  bool danger = false,
  IconData? icon,
}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final Color background = danger ? colors.error : (primary ? colors.primary : colors.surfaceContainerHighest);
  final Color foreground = danger ? colors.onError : (primary ? colors.onPrimary : colors.onSurface);
  final bool enabled = onPressed != null && !busy;
  final DVModifier look = const DVModifier()
      .paddingSymmetric(horizontal: 18, vertical: 12)
      .rounded(12)
      .backgroundColor(background)
      .color(foreground)
      .fontWeight(FontWeight.w700)
      .opacity(enabled ? 1 : 0.55)
      .minimumTapTarget()
      // One string is a control's tooltip and its name: the visible label
      // first, so the name contains what the reader sees, then what it does.
      .tooltip(busy ? '$label: working on it' : '$label: ${continuedSentence(tooltip)}');
  final Widget content = icon == null
      ? DVText(busy ? 'Please wait…' : label).modifier(const DVModifier().color(foreground).fontWeight(FontWeight.w700))
      : DVBox.row(
          <Widget>[
            Icon(icon, size: 18, color: foreground),
            DVText(busy ? 'Please wait…' : label)
                .modifier(const DVModifier().color(foreground).fontWeight(FontWeight.w700)),
          ],
          spacing: 8,
          crossAlign: DVCrossAlign.start,
          align: DVAlign.center,
        );
  return DVBox(
    content,
    onPressed != null && !busy ? look.hover(const DVModifier().opacity(0.9)).onTap(onPressed) : look,
  );
}

/// [text] continuing a sentence: its first letter lower-cased, unless it
/// starts an acronym such as "RTN".
String continuedSentence(String text) =>
    text.length < 2 || text[1].toUpperCase() == text[1] ? text : '${text[0].toLowerCase()}${text.substring(1)}';

/// A text field. [secret] hides what is typed, with the eye to show it.
@DVFunctionalWidget()
Widget _field(
  BuildContext context,
  String label, {
  required ValueChanged<String> onChanged,
  String value = '',
  String hint = '',
  String helper = '',
  bool secret = false,
  bool multiline = false,
  VoidCallback? onSubmitted,
}) => DVText(value).modifier(
  const DVModifier().input(
    label: label,
    hint: hint.isEmpty ? null : hint,
    helper: helper.isEmpty ? null : helper,
    obscureText: secret,
    multiline: multiline,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  ),
);

/// A message on the page: an error, a success or a hint.
@DVFunctionalWidget()
Widget _notice(BuildContext context, String message, {String tone = 'error'}) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  final (Color ink, IconData icon, String role) = switch (tone) {
    'good' => (dark ? RtnColors.goodLight : RtnColors.good, Icons.check_circle_outline, 'Done'),
    'info' => (Theme.of(context).colorScheme.primary, Icons.info_outline, 'Note'),
    _ => (dark ? RtnColors.badLight : RtnColors.bad, Icons.error_outline, 'Problem'),
  };
  return DVBox.row(
    <Widget>[
      Icon(icon, color: ink, size: 20, semanticLabel: role),
      Expanded(child: DVText(message).modifier(const DVModifier().color(ink).fontWeight(FontWeight.w600))),
    ],
    spacing: 10,
    modifier: const DVModifier().padding(12).rounded(12).backgroundColor(ink.withValues(alpha: 0.1)),
  );
}

/// Shown while a page's data is on its way.
@DVFunctionalWidget()
Widget _loading(BuildContext context, {String label = 'Loading'}) => DVBox(
  DVBox.row(
    <Widget>[
      SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5, semanticsLabel: label)),
      Flexible(child: DVText('$label…')),
    ],
    spacing: 12,
    crossAlign: DVCrossAlign.start,
  ),
  const DVModifier().padding(24),
);

/// A refusal from the backend, with a way to try again.
@DVFunctionalWidget()
Widget _refusal(BuildContext context, String message, {VoidCallback? onRetry}) => DVBox.list(<Widget>[
  Notice(message),
  if (onRetry != null) ActionButton('Try again', tooltip: 'Load this page again', onPressed: onRetry, primary: false),
], spacing: 12);

/// A labelled figure.
@DVFunctionalWidget()
Widget _stat(BuildContext context, String label, String value, {String tooltip = '', Color? ink}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  return DVBox.list(
    <Widget>[
      DVText(label).modifier(const DVModifier().color(colors.onSurfaceVariant).fontSize(13)),
      DVText(value)
          .modifier(const DVModifier().fontSize(20).fontWeight(FontWeight.w800).color(ink ?? colors.onSurface)),
    ],
    spacing: 2,
    crossAlign: DVCrossAlign.start,
    modifier: tooltip.isEmpty ? const DVModifier().minWidth(140) : const DVModifier().minWidth(140).tooltip(tooltip),
  );
}

/// A small label with a meaning, such as "Barred" or "Best value".
@DVFunctionalWidget()
Widget _tag(BuildContext context, String text, {String tooltip = '', bool warm = false}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final Color ink = warm ? colors.secondary : colors.primary;
  return DVText(text).modifier(
    const DVModifier()
        .paddingSymmetric(horizontal: 10, vertical: 4)
        .rounded(999)
        .backgroundColor(ink.withValues(alpha: 0.14))
        .color(ink)
        .fontSize(12)
        .fontWeight(FontWeight.w700)
        .tooltip(tooltip.isEmpty ? text : tooltip),
  );
}

/// One of a few choices, as a row of chips.
@DVFunctionalWidget()
Widget _choices(
  BuildContext context,
  List<String> options, {
  required String selected,
  required ValueChanged<String> onSelected,
  String what = 'option',
}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  return DVBox.wrapLine(<Widget>[
    for (final String option in options)
      DVText(option).modifier(
        const DVModifier()
            .paddingSymmetric(horizontal: 14, vertical: 9)
            .rounded(999)
            .backgroundColor(option == selected ? colors.primary : colors.surfaceContainerHighest)
            .color(option == selected ? colors.onPrimary : colors.onSurface)
            .fontWeight(FontWeight.w600)
            .tooltip(option == selected ? '$option: chosen as the $what' : '$option: choose it as the $what')
            .onTap(() => onSelected(option)),
      ),
  ], spacing: 8);
}

/// Text that says nothing is here yet.
@DVFunctionalWidget()
Widget _empty(BuildContext context, String message) =>
    DVText(message).modifier(const DVModifier().color(Theme.of(context).colorScheme.onSurfaceVariant).padding(8));

/// A link to another screen, drawn as a tile with an icon.
@DVFunctionalWidget()
Widget _linkTile(
  BuildContext context,
  DVRouteTarget to,
  String label, {
  required IconData icon,
  required String tooltip,
  String detail = '',
}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  return DVNavLink(
    to: to,
    semanticLabel: detail.isEmpty ? label : '$label. $detail',
    child: DVBox(
      DVBox.list(
        <Widget>[
          DVBox(
            Icon(icon, color: colors.primary, size: 26),
            const DVModifier().padding(10).rounded(14).backgroundColor(colors.primary.withValues(alpha: 0.12)),
          ),
          DVText(label).modifier(const DVModifier().fontWeight(FontWeight.w700)),
          if (detail.isNotEmpty)
            DVText(detail).modifier(const DVModifier().fontSize(12).color(colors.onSurfaceVariant)),
        ],
        spacing: 6,
        crossAlign: DVCrossAlign.start,
      ),
      const DVModifier()
          .padding(12)
          .rounded(16)
          .tooltip(tooltip)
          .hover(const DVModifier().backgroundColor(colors.primary.withValues(alpha: 0.06))),
    ),
  );
}

/// A plain text link to another screen.
@DVFunctionalWidget()
Widget _textLink(BuildContext context, DVRouteTarget to, String label, {required String tooltip}) => DVNavLink(
  to: to,
  semanticLabel: label,
  child: DVText(label).modifier(
    const DVModifier()
        .color(Theme.of(context).colorScheme.primary)
        .fontWeight(FontWeight.w700)
        .decoration(TextDecoration.underline)
        .tooltip(tooltip),
  ),
);

/// A screen's content: centred, readable width, scrolling.
@DVFunctionalWidget()
Widget _screen(BuildContext context, List<Widget> children, {double maxWidth = 760}) => DVBox.scrollableList(<Widget>[
  Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DVBox.list(children, spacing: 16),
    ),
  ),
], modifier: const DVModifier().paddingSymmetric(horizontal: 16, vertical: 20));
