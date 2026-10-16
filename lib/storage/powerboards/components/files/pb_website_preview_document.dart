import 'dart:convert';

import 'package:path/path.dart' as p;

String buildPbWebsitePreviewHtml({
  required String entryPath,
  required String html,
  required Map<String, String> textContentByPath,
  required Map<String, String> urlByPath,
}) {
  final knownPaths = <String>{...textContentByPath.keys, ...urlByPath.keys};
  final htmlPagePaths = textContentByPath.keys.where(_isWebsitePreviewHtmlPath).toSet();
  final rawPagesByPath = <String, String>{};

  for (final pagePath in htmlPagePaths) {
    final pageHtml = textContentByPath[pagePath];
    if (pageHtml == null) {
      continue;
    }

    rawPagesByPath[pagePath] = _buildRawWebsitePreviewPageHtml(
      pageHtml,
      currentPath: pagePath,
      knownPaths: knownPaths,
      htmlPagePaths: htmlPagePaths,
      textContentByPath: textContentByPath,
      urlByPath: urlByPath,
    );
  }

  final entryHtml = _buildRawWebsitePreviewPageHtml(
    html,
    currentPath: entryPath,
    knownPaths: knownPaths,
    htmlPagePaths: htmlPagePaths,
    textContentByPath: textContentByPath,
    urlByPath: urlByPath,
  );
  rawPagesByPath[entryPath] = entryHtml;
  return _injectWebsitePreviewBootstrap(rawHtml: entryHtml, rawPagesByPath: rawPagesByPath);
}

String _buildRawWebsitePreviewPageHtml(
  String html, {
  required String currentPath,
  required Set<String> knownPaths,
  required Set<String> htmlPagePaths,
  required Map<String, String> textContentByPath,
  required Map<String, String> urlByPath,
}) {
  var output = _inlineStylesheetLinks(
    html,
    entryPath: currentPath,
    knownPaths: knownPaths,
    textContentByPath: textContentByPath,
    urlByPath: urlByPath,
  );
  output = _rewriteStyleBlocks(output, entryPath: currentPath, knownPaths: knownPaths, urlByPath: urlByPath);
  output = _rewriteHtmlTags(output, entryPath: currentPath, knownPaths: knownPaths, htmlPagePaths: htmlPagePaths, urlByPath: urlByPath);
  output = _ensureWebsitePreviewBaseHref(output);
  return output;
}

String _injectWebsitePreviewBootstrap({required String rawHtml, required Map<String, String> rawPagesByPath}) {
  final registryJson = _escapeScriptTagText(jsonEncode(rawPagesByPath));
  const bootstrapScript = r'''
(function () {
  const pagesScriptId = 'pb-website-preview-pages';
  const pagesStorageKey = 'pbWebsitePreviewPages';
  const pendingFragmentKey = 'pbWebsitePreviewPendingFragment';
  const registryElement = document.getElementById(pagesScriptId);
  const inlinePagesJson = registryElement ? (registryElement.textContent || '') : '';
  const cachedPagesJson = window.sessionStorage ? (sessionStorage.getItem(pagesStorageKey) || '') : '';
  const pagesJson = inlinePagesJson || cachedPagesJson;
  if (!pagesJson) {
    return;
  }

  if (window.sessionStorage) {
    sessionStorage.setItem(pagesStorageKey, pagesJson);
  }

  let rawPages;
  try {
    rawPages = JSON.parse(pagesJson);
  } catch (_) {
    return;
  }

  const bootstrapSource = (document.currentScript && document.currentScript.textContent) || '';
  const escapedBootstrapSource = bootstrapSource.replace(/<\/script/gi, '<\\/script');

  function wrapHtml(rawHtml) {
    const escapedPagesJson = pagesJson.replace(/<\/script/gi, '<\\/script');
    const registryScriptTag =
      '<scr' +
      'ipt id="' +
      pagesScriptId +
      '" type="application/json">' +
      escapedPagesJson +
      '</scr' +
      'ipt>';
    const bootstrapScriptTag = '<scr' + 'ipt>' + escapedBootstrapSource + '</scr' + 'ipt>';
    const injection = registryScriptTag + bootstrapScriptTag;

    if (rawHtml.indexOf('</body>') >= 0) {
      return rawHtml.replace('</body>', injection + '</body>');
    }
    if (rawHtml.indexOf('</html>') >= 0) {
      return rawHtml.replace('</html>', injection + '</html>');
    }
    return rawHtml + injection;
  }

  window.__pbWebsitePreviewApplyFragment = function (fragment) {
    const normalizedFragment = fragment && fragment !== '#'
      ? (fragment.charAt(0) === '#' ? fragment : '#' + fragment)
      : '';

    if (!normalizedFragment) {
      if (window.location.hash) {
        try {
          history.replaceState(null, '', window.location.pathname + window.location.search);
        } catch (_) {
          window.location.hash = '';
        }
      }
      window.scrollTo(0, 0);
      return;
    }

    const targetId = decodeURIComponent(normalizedFragment.substring(1));
    const namedTarget = targetId ? document.getElementsByName(targetId)[0] : null;
    const target = (targetId ? document.getElementById(targetId) : null) || namedTarget;
    if (target && typeof target.scrollIntoView === 'function') {
      target.scrollIntoView();
    }

    if (window.location.hash !== normalizedFragment) {
      window.location.hash = normalizedFragment;
    }
  };

  window.__pbWebsitePreviewWrapHtml = wrapHtml;
  window.__pbWebsitePreviewNavigate = function (path, fragment) {
    const nextRawHtml = rawPages[path];
    if (typeof nextRawHtml !== 'string') {
      return;
    }

    if (window.sessionStorage) {
      sessionStorage.setItem(pagesStorageKey, pagesJson);
      if (fragment) {
        sessionStorage.setItem(pendingFragmentKey, fragment);
      } else {
        sessionStorage.removeItem(pendingFragmentKey);
      }
    }

    document.open();
    document.write(wrapHtml(nextRawHtml));
    document.close();
  };

  document.addEventListener('click', function (event) {
    let element = event.target;
    while (element && element.nodeType === Node.ELEMENT_NODE) {
      const tagName = element.tagName;
      const previewPage = element.getAttribute('data-pb-preview-page');
      const hasPreviewFragment = element.hasAttribute('data-pb-preview-fragment');
      if ((tagName === 'A' || tagName === 'AREA') && (previewPage || hasPreviewFragment)) {
        event.preventDefault();
        const fragment = element.getAttribute('data-pb-preview-fragment') || '';
        if (previewPage) {
          window.__pbWebsitePreviewNavigate(previewPage, fragment);
        } else {
          window.__pbWebsitePreviewApplyFragment(fragment);
        }
        return;
      }
      element = element.parentElement;
    }
  });

  if (window.sessionStorage) {
    const pendingFragment = sessionStorage.getItem(pendingFragmentKey);
    if (pendingFragment !== null) {
      sessionStorage.removeItem(pendingFragmentKey);
      requestAnimationFrame(function () {
        window.__pbWebsitePreviewApplyFragment(pendingFragment);
      });
    }
  }
})();
''';

  final injection = '<script id="pb-website-preview-pages" type="application/json">$registryJson</script><script>$bootstrapScript</script>';
  return _appendWebsitePreviewHtmlInjection(rawHtml, injection);
}

String _appendWebsitePreviewHtmlInjection(String html, String injection) {
  if (html.contains('</body>')) {
    return html.replaceFirst('</body>', '$injection</body>');
  }
  if (html.contains('</html>')) {
    return html.replaceFirst('</html>', '$injection</html>');
  }
  return '$html$injection';
}

String _ensureWebsitePreviewBaseHref(String html) {
  const baseTag = '<base href="https://meshagent.invalid/" />';
  if (RegExp(r'<base\b', caseSensitive: false).hasMatch(html)) {
    return html;
  }

  final headMatch = RegExp(r'<head\b[^>]*>', caseSensitive: false).firstMatch(html);
  if (headMatch != null) {
    final headTag = headMatch.group(0)!;
    return html.replaceFirst(headTag, '$headTag$baseTag');
  }

  final htmlMatch = RegExp(r'<html\b[^>]*>', caseSensitive: false).firstMatch(html);
  if (htmlMatch != null) {
    final htmlTag = htmlMatch.group(0)!;
    return html.replaceFirst(htmlTag, '$htmlTag<head>$baseTag</head>');
  }

  return '<head>$baseTag</head>$html';
}

String _inlineStylesheetLinks(
  String html, {
  required String entryPath,
  required Set<String> knownPaths,
  required Map<String, String> textContentByPath,
  required Map<String, String> urlByPath,
}) {
  return html.replaceAllMapped(RegExp(r'<link\b[^>]*>', caseSensitive: false), (match) {
    final tag = match.group(0)!;
    final rel = _extractAttribute(tag, 'rel')?.toLowerCase();
    if (rel == null || !rel.split(RegExp(r'\s+')).contains('stylesheet')) {
      return tag;
    }

    final href = _extractAttribute(tag, 'href');
    if (href == null) {
      return tag;
    }

    final resolvedPath = _resolveWebsitePreviewPath(currentPath: entryPath, reference: href, knownPaths: knownPaths);
    if (resolvedPath == null) {
      return tag;
    }

    final css = textContentByPath[resolvedPath];
    if (css == null) {
      return _rewriteAttributeReference(tag, attributeName: 'href', currentPath: entryPath, knownPaths: knownPaths, urlByPath: urlByPath);
    }

    final rewrittenCss = _rewriteCssReferences(css, currentPath: resolvedPath, knownPaths: knownPaths, urlByPath: urlByPath);
    return '<style data-pb-website-preview="$resolvedPath">$rewrittenCss</style>';
  });
}

String _rewriteStyleBlocks(
  String html, {
  required String entryPath,
  required Set<String> knownPaths,
  required Map<String, String> urlByPath,
}) {
  return html.replaceAllMapped(RegExp(r'(<style\b[^>]*>)([\s\S]*?)(</style>)', caseSensitive: false), (match) {
    final before = match.group(1)!;
    final css = match.group(2)!;
    final after = match.group(3)!;
    final rewrittenCss = _rewriteCssReferences(css, currentPath: entryPath, knownPaths: knownPaths, urlByPath: urlByPath);
    return '$before$rewrittenCss$after';
  });
}

String _rewriteHtmlTags(
  String html, {
  required String entryPath,
  required Set<String> knownPaths,
  required Set<String> htmlPagePaths,
  required Map<String, String> urlByPath,
}) {
  return html.replaceAllMapped(RegExp(r'<[A-Za-z][^>]*>', caseSensitive: false), (match) {
    var tag = match.group(0)!;
    if (tag.toLowerCase().startsWith('<style')) {
      return tag;
    }

    tag = _rewriteAttributeReference(tag, attributeName: 'src', currentPath: entryPath, knownPaths: knownPaths, urlByPath: urlByPath);
    tag = _rewriteAttributeReference(tag, attributeName: 'poster', currentPath: entryPath, knownPaths: knownPaths, urlByPath: urlByPath);
    tag = _rewriteHrefAttribute(tag, currentPath: entryPath, knownPaths: knownPaths, htmlPagePaths: htmlPagePaths, urlByPath: urlByPath);
    tag = _rewriteSrcsetAttribute(tag, currentPath: entryPath, knownPaths: knownPaths, urlByPath: urlByPath);
    tag = _rewriteStyleAttribute(tag, currentPath: entryPath, knownPaths: knownPaths, urlByPath: urlByPath);
    return tag;
  });
}

String _rewriteCssReferences(
  String css, {
  required String currentPath,
  required Set<String> knownPaths,
  required Map<String, String> urlByPath,
}) {
  return css.replaceAllMapped(RegExp(r'url\(\s*([^)]+?)\s*\)', caseSensitive: false), (match) {
    final rawValue = match.group(1)!.trim();
    final unquoted = _trimMatchingQuotes(rawValue);
    final replacement = _rewriteReferenceValue(reference: unquoted, currentPath: currentPath, knownPaths: knownPaths, urlByPath: urlByPath);
    if (replacement == unquoted) {
      return match.group(0)!;
    }

    return "url('$replacement')";
  });
}

String _rewriteAttributeReference(
  String tag, {
  required String attributeName,
  required String currentPath,
  required Set<String> knownPaths,
  required Map<String, String> urlByPath,
}) {
  return _replaceAttributeValue(tag, attributeName, (currentValue) {
    return _rewriteReferenceValue(reference: currentValue, currentPath: currentPath, knownPaths: knownPaths, urlByPath: urlByPath);
  });
}

String _rewriteHrefAttribute(
  String tag, {
  required String currentPath,
  required Set<String> knownPaths,
  required Set<String> htmlPagePaths,
  required Map<String, String> urlByPath,
}) {
  final anchorLikeTag = RegExp(r'^<\s*(a|area)\b', caseSensitive: false).hasMatch(tag);
  final href = _extractAttribute(tag, 'href');
  if (href == null) {
    return tag;
  }

  final normalizedLocalFragment = _normalizedPreviewFragment(href.trim());
  if (anchorLikeTag && normalizedLocalFragment != null) {
    var rewrittenTag = _replaceAttributeValue(tag, 'href', (_) => href.trim());
    rewrittenTag = _upsertAttribute(rewrittenTag, 'data-pb-preview-fragment', normalizedLocalFragment);
    return rewrittenTag;
  }

  final resolvedPath = _resolveWebsitePreviewPath(currentPath: currentPath, reference: href, knownPaths: knownPaths);
  if (resolvedPath != null && htmlPagePaths.contains(resolvedPath)) {
    final splitReference = _splitReference(href);
    final fragment = _normalizedPreviewFragment(splitReference.suffix) ?? '';
    if (resolvedPath == currentPath) {
      var rewrittenTag = _replaceAttributeValue(tag, 'href', (_) => fragment.isEmpty ? '#' : fragment);
      rewrittenTag = _upsertAttribute(rewrittenTag, 'data-pb-preview-fragment', fragment);
      return rewrittenTag;
    }

    var rewrittenTag = _replaceAttributeValue(tag, 'href', (_) => '#');
    rewrittenTag = _upsertAttribute(rewrittenTag, 'data-pb-preview-page', resolvedPath);
    if (fragment.isNotEmpty) {
      rewrittenTag = _upsertAttribute(rewrittenTag, 'data-pb-preview-fragment', fragment);
    }
    return rewrittenTag;
  }

  final rewrittenValue = _rewriteReferenceValue(reference: href, currentPath: currentPath, knownPaths: knownPaths, urlByPath: urlByPath);
  if (rewrittenValue != href) {
    return _replaceAttributeValue(tag, 'href', (_) => rewrittenValue);
  }

  if (anchorLikeTag && _shouldEscapePreviewHref(href)) {
    var rewrittenTag = tag;
    if (_extractAttribute(rewrittenTag, 'target') == null) {
      rewrittenTag = _upsertAttribute(rewrittenTag, 'target', '_blank');
    }

    final rel = _extractAttribute(rewrittenTag, 'rel');
    if (rel == null || rel.trim().isEmpty) {
      rewrittenTag = _upsertAttribute(rewrittenTag, 'rel', 'noopener noreferrer');
    }
    return rewrittenTag;
  }

  if (!anchorLikeTag || !_shouldBlockUnresolvedWebsitePreviewHref(href)) {
    return tag;
  }

  return _replaceAttributeValue(tag, 'href', (_) => '#');
}

String _rewriteSrcsetAttribute(
  String tag, {
  required String currentPath,
  required Set<String> knownPaths,
  required Map<String, String> urlByPath,
}) {
  return _replaceAttributeValue(tag, 'srcset', (currentValue) {
    return currentValue
        .split(',')
        .map((entry) {
          final trimmed = entry.trim();
          if (trimmed.isEmpty) {
            return trimmed;
          }

          final match = RegExp(r'^(\S+)(.*)$').firstMatch(trimmed);
          if (match == null) {
            return trimmed;
          }

          final reference = match.group(1)!;
          final descriptor = match.group(2) ?? '';
          final rewrittenReference = _rewriteReferenceValue(
            reference: reference,
            currentPath: currentPath,
            knownPaths: knownPaths,
            urlByPath: urlByPath,
          );
          return '$rewrittenReference$descriptor';
        })
        .join(', ');
  });
}

String _rewriteStyleAttribute(
  String tag, {
  required String currentPath,
  required Set<String> knownPaths,
  required Map<String, String> urlByPath,
}) {
  return _replaceAttributeValue(tag, 'style', (currentValue) {
    return _rewriteCssReferences(currentValue, currentPath: currentPath, knownPaths: knownPaths, urlByPath: urlByPath);
  });
}

String _rewriteReferenceValue({
  required String reference,
  required String currentPath,
  required Set<String> knownPaths,
  required Map<String, String> urlByPath,
}) {
  final resolvedPath = _resolveWebsitePreviewPath(currentPath: currentPath, reference: reference, knownPaths: knownPaths);
  if (resolvedPath == null) {
    return reference;
  }

  final rewritten = urlByPath[resolvedPath];
  if (rewritten == null || rewritten.isEmpty) {
    return reference;
  }

  final splitReference = _splitReference(reference);
  return '$rewritten${splitReference.suffix}';
}

({String reference, String suffix}) _splitReference(String reference) {
  final hashIndex = reference.indexOf('#');
  final queryIndex = reference.indexOf('?');
  final splitIndex = switch ((hashIndex, queryIndex)) {
    (-1, -1) => -1,
    (final hash, -1) => hash,
    (-1, final query) => query,
    (final hash, final query) => hash < query ? hash : query,
  };
  if (splitIndex < 0) {
    return (reference: reference, suffix: '');
  }

  return (reference: reference.substring(0, splitIndex), suffix: reference.substring(splitIndex));
}

String? _resolveWebsitePreviewPath({required String currentPath, required String reference, required Set<String> knownPaths}) {
  final trimmedReference = reference.trim();
  if (_isExternalWebsitePreviewReference(trimmedReference)) {
    return null;
  }

  final splitReference = _splitReference(trimmedReference);
  final bareReference = splitReference.reference;
  final rootPath = p.posix.split(currentPath).first;
  if (bareReference.isEmpty) {
    return knownPaths.contains(currentPath) ? currentPath : null;
  }

  if (bareReference == '/') {
    final rootEntryPath = p.posix.join(rootPath, 'index.html');
    return knownPaths.contains(rootEntryPath) ? rootEntryPath : null;
  }

  final baseDirectory = p.posix.dirname(currentPath);
  final resolvedPath = bareReference.startsWith('/')
      ? p.posix.normalize(p.posix.join(rootPath, bareReference.substring(1)))
      : p.posix.normalize(p.posix.join(baseDirectory, bareReference));
  if (resolvedPath != rootPath && !resolvedPath.startsWith('$rootPath/')) {
    return null;
  }

  return knownPaths.contains(resolvedPath) ? resolvedPath : null;
}

bool _shouldBlockUnresolvedWebsitePreviewHref(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) {
    return true;
  }

  if (trimmed.startsWith('//') ||
      trimmed.startsWith('data:') ||
      trimmed.startsWith('blob:') ||
      trimmed.startsWith('mailto:') ||
      trimmed.startsWith('tel:') ||
      trimmed.startsWith('javascript:')) {
    return false;
  }

  return !RegExp(r'^[A-Za-z][A-Za-z0-9+\-.]*:').hasMatch(trimmed);
}

bool _shouldEscapePreviewHref(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) {
    return false;
  }

  if (trimmed.startsWith('//') || trimmed.startsWith('mailto:') || trimmed.startsWith('tel:') || trimmed.startsWith('javascript:')) {
    return true;
  }

  return RegExp(r'^[A-Za-z][A-Za-z0-9+\-.]*:').hasMatch(trimmed);
}

bool _isWebsitePreviewHtmlPath(String path) {
  final normalized = path.trim().toLowerCase();
  return normalized.endsWith('.html') || normalized.endsWith('.htm');
}

String? _normalizedPreviewFragment(String value) {
  final trimmed = value.trim();
  if (!trimmed.startsWith('#')) {
    return null;
  }

  return trimmed == '#' ? '' : trimmed;
}

bool _isExternalWebsitePreviewReference(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.startsWith('#') ||
      trimmed.startsWith('//') ||
      trimmed.startsWith('data:') ||
      trimmed.startsWith('blob:') ||
      trimmed.startsWith('mailto:') ||
      trimmed.startsWith('tel:') ||
      trimmed.startsWith('javascript:')) {
    return true;
  }

  return RegExp(r'^[A-Za-z][A-Za-z0-9+\-.]*:').hasMatch(trimmed);
}

String? _extractAttribute(String tag, String attributeName) {
  final match = RegExp('$attributeName\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false).firstMatch(tag);
  return match?.group(1) ?? match?.group(2) ?? match?.group(3);
}

String _upsertAttribute(String tag, String attributeName, String value) {
  final escapedValue = _escapeHtmlAttributeValue(value);
  final attributePattern = RegExp('($attributeName\\s*=\\s*)(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false);
  if (attributePattern.hasMatch(tag)) {
    return tag.replaceFirstMapped(attributePattern, (match) {
      return '${match.group(1)}"$escapedValue"';
    });
  }

  final closingIndex = tag.lastIndexOf('>');
  if (closingIndex < 0) {
    return tag;
  }

  final insertIndex = closingIndex > 0 && tag[closingIndex - 1] == '/' ? closingIndex - 1 : closingIndex;
  return '${tag.substring(0, insertIndex)} $attributeName="$escapedValue"${tag.substring(insertIndex)}';
}

String _replaceAttributeValue(String tag, String attributeName, String Function(String currentValue) replace) {
  return tag.replaceFirstMapped(RegExp('($attributeName\\s*=\\s*)(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false), (match) {
    final currentValue = match.group(2) ?? match.group(3) ?? match.group(4);
    if (currentValue == null) {
      return match.group(0)!;
    }

    final nextValue = replace(currentValue);
    if (nextValue == currentValue) {
      return match.group(0)!;
    }

    return '${match.group(1)}"${_escapeHtmlAttributeValue(nextValue)}"';
  });
}

String _escapeHtmlAttributeValue(String value) {
  return value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

String _escapeScriptTagText(String value) {
  return value.replaceAll(RegExp(r'</script', caseSensitive: false), '<\\/script');
}

String _trimMatchingQuotes(String value) {
  if (value.length < 2) {
    return value;
  }

  final first = value[0];
  final last = value[value.length - 1];
  if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
    return value.substring(1, value.length - 1);
  }

  return value;
}
