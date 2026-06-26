import 'package:flutter/widgets.dart';

/// Returns the name of the currently-active route by inspecting the live
/// element tree — no [NavigatorObserver] required. Works with MaterialApp.routes,
/// MaterialApp.router, go_router, and Navigator 2.0.
///
/// Implementation notes (why we don't use [ModalRoute.of]):
/// [ModalRoute.of] calls [InheritedModel.inheritFrom] which registers the
/// caller element as a dependent on the [_ModalScopeStatus] InheritedElement.
/// When called on arbitrary elements outside a build, those registrations
/// persist and corrupt the dependency graph, causing Flutter framework assertions
/// when routes later change (InheritedElement.notifyClients verification fails).
///
/// Instead we walk the element tree in DFS order, collecting all elements whose
/// widget type name is '_ModalScopeStatus' (Flutter's private InheritedModel that
/// holds the route). We take the LAST one in DFS order because routes in the
/// Navigator's Overlay are appended as later siblings — i.e., the topmost/active
/// route appears last in DFS traversal, not necessarily the deepest by nesting
/// depth. We read the route name via dynamic dispatch (no private type import
/// required). This is entirely read-only and never registers any dependencies.
String? resolveCurrentRouteName() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;

  // Collect all _ModalScopeStatus route names in DFS order.
  // The last entry corresponds to the topmost (active) route because
  // Flutter's Overlay appends later-pushed routes as later siblings.
  final names = <String>[];

  void dfs(Element e) {
    if (e is InheritedElement &&
        e.widget.runtimeType.toString() == '_ModalScopeStatus') {
      try {
        // _ModalScopeStatus.route is private to read by type, but the value is a
        // public [Route]; cast to it so we use only public APIs after that.
        // ignore: avoid_dynamic_calls
        final route = (e.widget as dynamic).route;
        if (route is Route) {
          // Named routes report settings.name; anonymous routes fall back to
          // their runtime type so they are still identifiable.
          names.add(route.settings.name ?? route.runtimeType.toString());
        }
      } catch (_) {
        // Defensive: skip any element that doesn't conform to expectations.
      }
    }
    e.visitChildren(dfs);
  }

  dfs(root);
  return names.isEmpty ? null : names.last;
}
