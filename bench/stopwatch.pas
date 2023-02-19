unit stopwatch;

interface
{$mode delphi}{$H+}


type
  TTicksType = int64;


  { TStopWatch }

  TStopWatch = record
    FStart, FFinish: TTicksType;
    procedure Reset;
    procedure Start;
    procedure Stop;
    function ElapsedMilliseconds: int64;
    class function Create: TStopWatch;static;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ELSE}
  Unix,
  {$ENDIF}

  SysUtils;

var
  QFrequency: TTicksType;

  {$IFNDEF MSWINDOWS}
  procedure QueryPerformanceCounter(var q: TTicksType);
  var
      timerTimeVal : TimeVal;
  begin
    fpGetTimeOfDay( @timerTimeVal, nil );
    q := timerTimeVal.tv_sec * 1000 + timerTimeVal.tv_usec div 1000;
  end;

  function QueryPerformanceFrequency(var q: TTicksType): boolean;
  begin
    q := 1000;
    Result := true;
  end;
  {$ENDIF}


  { TStopWatch }

procedure TStopWatch.Reset;
begin

end;

procedure TStopWatch.Start;
begin
  QueryPerformanceCounter(FStart);
end;

procedure TStopWatch.Stop;
begin
  QueryPerformanceCounter(FFinish);
end;

function TStopWatch.ElapsedMilliseconds: int64;
begin
  Result := round((FFinish - FStart)*1000/QFrequency);
end;

class function TStopWatch.Create: TStopWatch;
begin

end;


begin
  QueryPerformanceFrequency(QFrequency);
end.
