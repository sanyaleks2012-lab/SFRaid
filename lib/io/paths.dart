final RegExp _pkgRe =
    RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$');

bool isValidPackage(String pkg) => _pkgRe.hasMatch(pkg);

String gamedataDir(String pkg) =>
    '/storage/emulated/0/Android/data/$pkg/files/mod/gamedata';
