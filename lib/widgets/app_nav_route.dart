/// Sol gezinme menüsündeki (sidebar/drawer) her bir hedefin kimliği.
///
/// Bu enum, [NavigationShell]'in "şu an hangi ekranda olduğumuzu" bilip aktif
/// öğeyi vurgulayabilmesi (`aktif öğe vurgulu`) için var. Bilinçli olarak
/// kendi (screen importu olmayan) dosyasında tutuluyor — hem ekranların hem
/// `app_nav_items.dart`/`navigation_shell.dart`'ın bu enum'a ihtiyacı var, ama
/// ekranların `app_nav_items.dart`'a (o dosya tüm ekranları import ediyor)
/// bağımlı olmasına gerek yok; bu ayrım gereksiz bir döngüsel importu önlüyor.
enum AppNavRoute {
  home,
  createRequest,
  myRequests,
  incomingRequests,
  messages,
  invite,
  departments,
  users,
  stats,
  emailChangeRequests,
  profile,
  settings,
  logout,
}
