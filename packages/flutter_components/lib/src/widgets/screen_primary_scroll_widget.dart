/// Marker interface for widgets that own the primary scroll region of a screen.
///
/// Used by higher-level layout templates to avoid nesting scrollables (e.g.
/// placing a ListView inside a SingleChildScrollView), which can lead to
/// unbounded viewport errors.
abstract interface class ScreenPrimaryScrollWidget {}
