import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart';

class CodePreview extends StatefulWidget {
  const CodePreview({super.key, required this.url});

  final Uri url;

  @override
  State createState() => _CodePreview();
}

class _CodePreview extends State<CodePreview> {
  String? text;

  @override
  void initState() {
    super.initState();

    get(widget.url).then((response) {
      if (!mounted) return;

      setState(() {
        text = response.body;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return text == null
        ? Center(child: CircularProgressIndicator())
        : SizedBox(
          width: 700,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 5),
            child: ColoredBox(
              color: Colors.black,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SelectableText(
                  text!,
                  style: GoogleFonts.sourceCodePro(color: Color.from(alpha: 1, red: .8, green: .8, blue: .8), fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        );
  }
}
