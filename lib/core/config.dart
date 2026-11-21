// Константы, пресеты перков и правил, теги, которые можно удалять.

const int maxUndo = 30;

const String defaultFilePath =
    '/storage/emulated/0/raid_stages_default.xml';

const Map<String, (String, String, Map<String, String>)> presetPerks = {
  '1': ('OVERHEAT', 'PERK_ITEM_SPECIAL_OVERHEAT_WEAPON', {
    'Aspect': '100000',
    'Frames': '300'
  }),
  '2': ('BLEEDING', 'PERK_ITEM_SPECIAL_BLEEDING_WEAPON', {
    'Aspect': '100000'
  }),
  '3': ('DAMAGE ABSORPTION',
      'PERK_ITEM_SPECIAL_DAMAGE_ABSORBPTION_BODY_ARMOR', {
    'Aspect': '100000',
    'Chance': '0.2'
  }),
  '4': ('INVISIBILITY', 'PERK_INVISIBILITY', {'Frames': '600'}),
  '5': ('BLOCK BREAKER', 'PERK_BLOCK_BREAKER', {'Chance': '0.33'}),
  '6': ('PAIN RAGE', 'PERK_PAIN_RAGE', {
    'Chance': '0.25',
    'DamageFactor': '3000'
  }),
  '7': ('PLOT TWIST', 'PERK_PLOT_TWIST', {
    'Chance': '1.0',
    'Type': 'CopyMagic'
  }),
  '8': ('SOUL TYPHOON', 'PERK_SOUL_TYPHOON', {'Aspect': '100000'}),
  '9': ('TIME SHIFT', 'PERK_TIME_SHIFT', {'Frames': '300'}),
  '10': ('CRIMSON CORRUPTION', 'PERK_CRIMSON_CORRUPTION', {
    'Aspect': '100000'
  }),
  '11': ('ROARING LIGHT', 'PERK_ROARING_LIGHT', {'Aspect': '100000'}),
};

const Map<String, (String, String, String, Map<String, String>)> presetRules = {
  '1': ('HOT GROUND', 'HOT_GROUND', 'HotGround', {
    'Frames': '720',
    'ApplyTo': 'Player'
  }),
  '2': ('INVERTED JOYSTICK', 'INVERTED_JOYSTICK', 'InvertJoystick', {}),
  '3': ('NO HEALTH BAR', 'NO_HEALTHBAR', 'NoHealthBar', {}),
  '4': ('NO JUMPS', 'NO_JUMPS', 'NoAnimation', {'Name': 'Jump'}),
  '5': ('NO KICKS', 'NO_KICKS', 'NoButton', {
    'Name': 'Kick',
    'ApplyTo': 'Player'
  }),
  '6': ('NO BLOCKS', 'NO_BLOCKS', 'RemoveInterval', {
    'Type': 'Block',
    'ApplyTo': 'Player'
  }),
};

const Set<String> removableRuleTags = {
  'Avatar',
  'Name',
  'EquipItem',
  'Perk',
  'ComplexRule',
  'RulesWithConditions',
};
