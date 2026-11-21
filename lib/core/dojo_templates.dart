// Шаблоны XML-квестов для Dojo Changer.

const String dojoPageTemplate = r'''
<Quest Name="">
  <Events>
    <Activate />
  </Events>
  <Conditions>
    <Equal Value1="_$ActionID" Value2="" />
  </Conditions>
  <Actions>
    <Dialog Type="Multiline" Title="DojoChangerTitle" Image="man_random_small">
      <Line Text="" />
      <Button Type="Right" Color="Beige" Text="NEXT">
        <Activate ActionID="" />
      </Button>
      <Button Type="Middle" Color="Green" Text="SELECT">
        <Activate ActionID="" />
      </Button>
      <Button Type="Left" Color="Red" Text="BACK" />
      <CheckBox Text="ShowIntro" InitialValue="_ShowIntroVideo">
        <On>
          <SetVariable Scope="Users" Name="ShowIntroVideo" Value="1" />
        </On>
        <Off>
          <SetVariable Scope="Users" Name="ShowIntroVideo" Value="0" />
        </Off>
      </CheckBox>
    </Dialog>
  </Actions>
</Quest>''';

const String dojoLoadTemplate = r'''
<Quest Name="">
  <Events>
    <Activate />
  </Events>
  <Conditions>
    <Equal Value1="_$ActionID" Value2="" />
  </Conditions>
  <Actions>
    <ChangeDojoLocation Name="" />
    <ChangeScene Destination="Dojo" />
    <SetVariable Scope="Users" Name="DojoLoader" Value="" />
  </Actions>
</Quest>''';

const String dojoStartupQuestTemplate = '''
<Quest Name="DojoChanger_LoadSelectedDojo" Priority="999">
  <Events>
    <ApplicationStart />
  </Events>
  <Actions />
</Quest>''';

const String dojoStartupIfTemplate = '''
<If>
  <Conditions>
    <Equal Value1="_DojoLoader" Value2="" />
  </Conditions>
  <Then>
    <ChangeDojoLocation Name="" />
  </Then>
</If>''';
