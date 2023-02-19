program benchmark;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  ecs in '..\ecs.pas',
  uTests in 'uTests.pas',
  uBenchmark in 'uBenchmark.pas';

begin
  ReportMemoryLeaksOnShutdown := True;
  DoTests;
  readln;
end.
