import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

class ImpressumPage extends StatelessWidget {
  const ImpressumPage({super.key});

  static const _kTaxNumber = '18064333-2-42';
  static const _kProjectUrl =
      'https://github.com/szentjozsefhackathon/ignaci_imak';

  @override
  Widget build(BuildContext context) {
    final textStyle =
        Theme.of(context).textTheme.titleMedium ?? const TextStyle();
    return Scaffold(
      appBar: AppBar(title: const Text('Impresszum')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Center(
          child: DefaultTextStyle(
            style: textStyle,
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: textStyle,
                children: [
                  const TextSpan(
                    text:
                        'Jézus Társasága Magyarországi Rendtartománya\n'
                        'Ignáci Pedagógiai Műhely\n\n'
                        '1085 Budapest, Horánszky u. 20.\n\n',
                  ),
                  LinkSpan(
                    urlLabel: 'ignacipedagogia.hu',
                    url: 'https://ignacipedagogia.hu',
                  ),
                  const TextSpan(text: '\n\n'),
                  LinkSpan(urlLabel: 'jezsuita.hu', url: 'https://jezsuita.hu'),
                  const TextSpan(
                    text:
                        '\n\n'
                        'Ha támogatni szeretnéd munkánkat, ajánld fel adód 1%-át a Jézus Társasága Alapítványnak.\n\nAdószám:',
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: InlineButton(
                      label: const Text(_kTaxNumber),
                      suffix: const Icon(Icons.copy_rounded),
                      onPressed: () async {
                        await Clipboard.setData(
                          const ClipboardData(text: _kTaxNumber),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text('Adószám vágólapra másolva'),
                              ),
                            );
                        }
                      },
                    ),
                  ),
                  const WidgetSpan(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Divider(),
                    ),
                  ),
                  const TextSpan(
                    text:
                        'Felújítva 2025-ben, a Szent József Hackathon keretein belül.\n\nHa fejlesztenél valamit az alkalmazáson, akkor',
                  ),
                  LinkSpan(urlLabel: 'itt találod', url: _kProjectUrl),
                  const TextSpan(text: 'a nyílt forráskódú projektet.'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LinkSpan extends WidgetSpan {
  LinkSpan({
    required String urlLabel,
    required String url,
    super.alignment = PlaceholderAlignment.baseline,
    super.baseline = TextBaseline.alphabetic,
  }) : super(
         child: LinkButton(urlLabel: urlLabel, url: url),
       );
}

class LinkButton extends InlineButton {
  LinkButton({super.key, required String urlLabel, required String url})
    : super(
        onPressed: () => _launchUrl(url),
        label: Text(urlLabel),
        suffix: const Icon(Icons.open_in_new_rounded),
      );

  static Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);

    if (!await launchUrl(uri)) {
      throw 'Could not launch $uri';
    }
  }
}

class InlineButton extends StatelessWidget {
  const InlineButton({
    super.key,
    required this.label,
    required this.suffix,
    required this.onPressed,
  });

  final Widget label;
  final Widget? suffix;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(
      backgroundColor: Colors.transparent,
      overlayColor: Colors.transparent,
      textStyle: DefaultTextStyle.of(context).style,
    ),
    onPressed: onPressed,
    icon: suffix,
    iconAlignment: IconAlignment.end,
    label: label,
  );
}
