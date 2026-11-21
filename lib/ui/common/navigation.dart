import 'package:flutter/material.dart';

void go(BuildContext c, Widget w) {
  Navigator.of(c).push(
    MaterialPageRoute(builder: (_) => w),
  );
}
