program VclEcs;

uses
  Vcl.Forms,
  uMain in 'uMain.pas' {Form1},
  ecs in '..\ecs.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
