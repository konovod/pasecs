program benchmark;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  ecs in '..\ecs.pas',
  uTests in 'uTests.pas';

begin
  DoTests;
  readln;

end.
