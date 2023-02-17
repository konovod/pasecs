program benchmark;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  ecs in '..\ecs.pas',
  uApp in 'uApp.pas';

begin
  DoTests;
  writeln('Tests passed');
  readln;
end.
