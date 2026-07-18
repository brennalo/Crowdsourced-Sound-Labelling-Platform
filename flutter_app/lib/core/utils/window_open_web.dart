import 'dart:html' as html;

Object? openBlankWindow() => html.window.open('', '_blank');

void redirectWindow(Object? window, String url) {
  (window as html.WindowBase).location.href = url;
}
