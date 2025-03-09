# screenwriter_editor

A script editor that simply implements Fountain syntax highlighting.

- [Fountain syntax](https://fountain.io/syntax/)

It is only compatible with common situations. It is possible that highlighting may fail in some complex grammar situations.

In the script source file, you can configure a rule of characters per minute to estimate the script time.   
(Set a json value through the `Metadata` key of the Title Page. In the json object, set the `chars_per_minu` field to specify the estimated rule of how many characters per minute.)  
If not configured, the default rule of `243.22` characters per minute is used to estimate the script time.

Configure the rule of 250 characters per minute to estimate the script time. Example:
```
Metadata: {
    "chars_per_minu": 250.0
}
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
