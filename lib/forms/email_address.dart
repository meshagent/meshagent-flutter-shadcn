class Address {
  const Address(this.mailAddress, [this.name]);

  final String? name;
  final String mailAddress;

  static final _quotableNameRegExp = RegExp(r'[",]');

  String? get sanitizedName {
    final currentName = name;
    if (currentName == null) {
      return null;
    }

    if (currentName.contains(_quotableNameRegExp)) {
      return '"${currentName.replaceAll('"', r'\"')}"';
    }

    return currentName;
  }

  String get sanitizedAddress => mailAddress;

  @override
  String toString() => name == null ? mailAddress : "$name <$mailAddress>";
}

List<Address> parseEmailList(String addresses) {
  final result = <Address>[];
  final nameOrEmail = <int>[];
  final email = <int>[];
  final name = <int>[];

  final commaCodeUnit = ",".codeUnitAt(0);
  final semicolonCodeUnit = ";".codeUnitAt(0);
  final quoteCodeUnit = '"'.codeUnitAt(0);
  final openAngleBracket = "<".codeUnitAt(0);
  final closeAngleBracket = ">".codeUnitAt(0);
  final backslashCodeUnit = r"\".codeUnitAt(0);

  var inQuote = false;
  var inAngleBrackets = false;

  void addAddress() {
    if (nameOrEmail.isNotEmpty) {
      if (email.isEmpty) {
        email.addAll(nameOrEmail);
      } else if (name.isEmpty) {
        name.addAll(nameOrEmail);
      }
    }

    if (email.isNotEmpty) {
      final parsedName = String.fromCharCodes(name).trim();
      result.add(Address(String.fromCharCodes(email).trim(), parsedName.isEmpty ? null : parsedName));
    }

    email.clear();
    name.clear();
    nameOrEmail.clear();
    inAngleBrackets = false;
    inQuote = false;
  }

  final codeUnits = addresses.codeUnits;
  for (int p = 0; p < codeUnits.length; p++) {
    final c = codeUnits[p];

    if (inQuote) {
      if (c == quoteCodeUnit) {
        inQuote = false;
      } else if (c == backslashCodeUnit) {
        ++p;
        if (p < codeUnits.length) {
          name.add(codeUnits[p]);
        }
      } else {
        name.add(c);
      }
    } else if (inAngleBrackets) {
      if (c == closeAngleBracket) {
        inAngleBrackets = false;
      } else {
        email.add(c);
      }
    } else if (c == commaCodeUnit || c == semicolonCodeUnit) {
      addAddress();
    } else if (c == quoteCodeUnit) {
      inQuote = true;
    } else if (c == openAngleBracket) {
      inAngleBrackets = true;
    } else {
      nameOrEmail.add(c);
    }
  }

  addAddress();

  return result;
}
