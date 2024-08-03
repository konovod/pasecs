program benchmark;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  ecs in '..\ecs.pas',
  uTests in 'uTests.pas',
  {$IFNDEF FPC}
  ecs_serializer in '..\ecs_serializer.pas' ,
  uSerializationTests in 'uSerializationTests.pas' ,
  uKBDynamic in '..\uKBDynamic.pas',
  {$ENDIF }
  uBenchmark in 'uBenchmark.pas'
  ;

begin
  ReportMemoryLeaksOnShutdown := True;
  DoTests;
  {$IFNDEF FPC}
  DoSerializationTests;
  {$ENDIF }
  DoBenchmarks;
  readln;
end.
