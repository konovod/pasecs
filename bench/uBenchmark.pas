unit uBenchmark;

{$IFDEF FPC}
{$mode Delphi}{$H+}
{$ENDIF}

interface

uses ecs;

const
  BENCH_N = 1000000;

type
  TComp1 = record
    x, y: integer;
    constructor Create(x, y: integer);
  end;

  TComp2 = record
    name: string;
    constructor Create(name: string);
  end;

  TComp3 = record
    heavy: array [1 .. 64] of integer;
    constructor Create(v: integer);
  end;

  TComp4 = record
  end;

  TComp5 = record
    vx, vy: integer;
    constructor Create(vx, vy: integer);
  end;

function UsedMemory: integer;

procedure DoBenchmarks;

implementation

uses
{$IFDEF FPC}
  stopwatch,
{$ELSE}
  System.Diagnostics,
{$ENDIF}
  SysUtils;

var
  watch: TStopwatch;
  world: TECSWorld;
  sys: TECSSystems;

type
  TBenchProc = procedure;

{$IFDEF FPC}

function UsedMemory: integer;
begin
  Result := GetFPCHeapStatus.CurrHeapUsed;
end;
{$ELSE}

function UsedMemory: integer;
var
  state: TMemoryManagerState;
  small: TSmallBlockTypeState;
begin
  GetMemoryManagerState(state);
  Result := state.TotalAllocatedMediumBlockSize +
    state.TotalAllocatedLargeBlockSize;
  for small in state.SmallBlockTypeStates do
    Inc(Result, small.AllocatedBlockCount * small.UseableBlockSize)
end;
{$ENDIF}

function Benchmark(x: TBenchProc): integer; // return microseconds
var
  I: integer;
begin
  x();
  watch.Reset;
  watch.Start;
  for I := 1 to 10 do // warmup
    x();
  watch.Stop;
  if watch.ElapsedMilliseconds >= 500 then
  begin
    Result := watch.ElapsedMilliseconds * 100;
    exit;
  end;

  watch.Reset;
  watch.Start;
  for I := 1 to 1000 do
    x();
  watch.Stop;
  Result := watch.ElapsedMilliseconds;
end;

function InitBenchmarkWorld: TECSWorld;
var
  ent: TECSEntity;
  I: integer;
begin
  Result := TECSWorld.Create;

  // config = Config.new(Hash(String, Int32).new)
  // config.values["value"] = 1
  // world.new_entity.add(config)
  ent := Result.NewEntity;
  ent.Add<TComp5>(TComp5.Create(0, 0));
  ent.Remove<TComp5>;
  // {% for i in 1..BENCH_COMPONENTS %}
  // world.new_entity.add(BenchComp{{i}}.new({{i}},{{i}}))
  // {% end %}
  //
  for I := 1 to BENCH_N do
  begin
    ent := Result.NewEntity;
    if I mod 2 = 0 then
      ent.Add<TComp1>(TComp1.Create(I, I));
    if I mod 3 = 0 then
      ent.Add<TComp2>(TComp2.Create(IntToStr(I)));
    if I mod 5 = 0 then
      ent.Add<TComp3>(TComp3.Create(I));
    if I mod 7 = 0 then
      ent.Add<TComp4>;

    ent.Add<TComp5>(TComp5.Create(0, 0));
    ent.Remove<TComp5>;
  end;
end;

procedure BenchBenchmarkWorld;
var
  w: TECSWorld;
begin
  w := InitBenchmarkWorld;
  w.Free;
end;

type
  TEmptySystem = class(TECSSystem)
  end;

  TEmptyFilterSystem = class(TECSSystem)
  public
    count: integer;
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
  end;

  TAddDeleteSingleComponent = class(TECSSystem)
    procedure Execute; override;
  end;

  TAddDeleteFourComponents = class(TECSSystem)
    procedure Execute; override;
  end;

  TAskComponent<Positive> = class(TECSSystem)
  public
    ent: TECSEntity;
    found: Boolean;
    procedure Execute; override;
    procedure Init; override;
    procedure Teardown; override;
  end;

  TGetComponent<Positive> = class(TECSSystem)
  public
    ent: TECSEntity;
    found: Positive;
    procedure Execute; override;
    procedure Init; override;
    procedure Teardown; override;
  end;

  TCountComp1 = class(TECSSystem)
  public
    count: integer;
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
  end;

  TUpdateComp1 = class(TECSSystem)
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
  end;

  TUpdateComp1UsingPtr = class(TECSSystem)
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
  end;

  TReplaceComp1 = class(TECSSystem)
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
  end;

  TReplaceComp5 = class(TECSSystem)
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
  end;

  TReplaceComps = class(TECSSystems)
    constructor Create(AOwner: TECSWorld); override;
  end;

  TComplexFilter = class(TECSSystem)
  public
    count: integer;
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
        procedure Execute; override;

  end;

procedure BenchExec;
begin
  sys.Execute;
end;

procedure BenchExec1000;
var
  I: integer;
begin
  for I := 1 to 1000 do
    sys.Execute;
end;

procedure BenchSystemExecution(typ: TECSSystemClass);
var
  I: integer;
begin
  sys := TECSSystems.Create(world);
  sys.Add(typ);
  sys.Init;
  I := Benchmark(BenchExec);
  sys.Teardown;
  sys.Free;
  writeln(typ.ClassName, ': ', I, ' us');
end;

procedure BenchSystemExecutionNS(typ: TECSSystemClass);
var
  I: integer;
begin
  sys := TECSSystems.Create(world);
  sys.Add(typ);
  sys.Init;
  I := Benchmark(BenchExec1000);
  sys.Teardown;
  sys.Free;
  writeln(typ.ClassName, ': ', I, ' ns');
end;

procedure DoBenchmarks;
var
  mem: integer;
  stat: TECSWorld.TStatsPair;
begin
  mem := UsedMemory;
  world := InitBenchmarkWorld;
  writeln('benchmark world size: ', (UsedMemory - mem) / 1000000:0:6, ' MB');
  writeln('Stats: ');
  for stat in world.Stats do
    writeln('  ', stat.Key, ': ', stat.Value);

  writeln('create and clear benchmark world: ',
    Benchmark(BenchBenchmarkWorld), ' us');

  BenchSystemExecutionNS(TEmptySystem);
  BenchSystemExecutionNS(TEmptyFilterSystem);

  BenchSystemExecutionNS(TAddDeleteSingleComponent);
  BenchSystemExecutionNS(TAddDeleteFourComponents);

  BenchSystemExecutionNS(TAskComponent<TComp1>);
  BenchSystemExecutionNS(TAskComponent<TComp5>);
  BenchSystemExecutionNS(TGetComponent<TComp1>);
  BenchSystemExecutionNS(TGetComponent<TComp5>);

  BenchSystemExecution(TCountComp1);
  BenchSystemExecution(TUpdateComp1);
  BenchSystemExecution(TUpdateComp1UsingPtr);

  BenchSystemExecution(TReplaceComps);
  BenchSystemExecution(TComplexFilter);

  // SystemGetSingletonComponent 130.97M (  7.64ns) (± 1.19%)  0.0B/op   1.39× slower
  // IterateOverCustomFilterSystem  75.59M ( 13.23ns) (± 1.17%)  0.0B/op   2.41× slower
  // ***********************************************
  // SystemPassEvents  32.59  ( 30.68ms) (± 0.37%)  0.0B/op   9.12× slower
  // ***********************************************
  // FullFilterSystem 169.08  (  5.91ms) (± 0.21%)  0.0B/op   1.76× slower
  // FullFilterAnyOfSystem 125.96  (  7.94ms) (± 0.21%)  0.0B/op   2.36× slower

  // SystemComplexSelectFilter 286.01  (  3.50ms) (± 0.81%)  0.0B/op   1.04× slower

  world.Free;
  writeln('Benchmark complete');
end;

{ TComp1 }

constructor TComp1.Create(x, y: integer);
begin
  Self.x := x;
  Self.y := y;
end;

{ TComp2 }

constructor TComp2.Create(name: string);
begin
  Self.name := name;
end;

{ TComp3 }

constructor TComp3.Create(v: integer);
var
  I: integer;
begin
  for I := 1 to 64 do
    Self.heavy[I] := v + I;
end;

{ TComp5 }

constructor TComp5.Create(vx, vy: integer);
begin
  Self.vx := vx;
  Self.vy := vy;
end;

{ TEmptyFilterSystem }

function TEmptyFilterSystem.Filter: TECSFilter;
begin
  Result := world.Filter.Include<TComp5>;
end;

procedure TEmptyFilterSystem.Process(e: TECSEntity);
begin
  Inc(Count)
end;

{ TAddDeleteSingleComponent }

procedure TAddDeleteSingleComponent.Execute;
var
  ent: TECSEntity;
begin
  ent := world.NewEntity;
  ent.Add<TComp1>(TComp1.Create(-1, -1));
  ent.Remove<TComp1>;
end;

{ TAddDeleteFourComponents }

procedure TAddDeleteFourComponents.Execute;
var
  ent: TECSEntity;
begin
  ent := world.NewEntity;
  ent.Add<TComp1>(TComp1.Create(-1, -1));
  ent.Add<TComp2>(TComp2.Create('-1'));
  ent.Add<TComp3>(TComp3.Create(-1));
  ent.Add<TComp4>;
  ent.RemoveAll;
end;

{ TAskComponent<Positive> }

procedure TAskComponent<Positive>.Execute;
begin
  found := found xor (ent.Has<Positive>)
end;

procedure TAskComponent<Positive>.Init;
begin
  ent := world.NewEntity;
  ent.Add<TComp1>(TComp1.Create(-1, -1));
end;

procedure TAskComponent<Positive>.Teardown;
begin
  ent.RemoveAll;
  if PInteger(@found)^ = 1000 then
    writeln('');
end;

{ TGetComponent<Positive> }

procedure TGetComponent<Positive>.Execute;
begin
  ent.TryGet<Positive>(found);
end;

procedure TGetComponent<Positive>.Init;
begin
  ent := world.NewEntity;
  ent.Add<TComp1>(TComp1.Create(-1, -1));
end;

procedure TGetComponent<Positive>.Teardown;
begin
  ent.RemoveAll;
  if PInteger(@found)^ = 1000 then
    writeln('');
end;

{ TCountComp1 }

function TCountComp1.Filter: TECSFilter;
begin
  Result := world.Filter.Include<TComp1>
end;

procedure TCountComp1.Process(e: TECSEntity);
begin
  Inc(count);
end;

{ TUpdateComp1 }

function TUpdateComp1.Filter: TECSFilter;
begin
  Result := world.Filter.Include<TComp1>
end;

procedure TUpdateComp1.Process(e: TECSEntity);
var
  c: TComp1;
begin
  c := e.Get<TComp1>;
  c.x := -c.x;
  c.y := -c.y;
  e.Update<TComp1>(c);
end;

{ TUpdateComp1UsingPtr }

function TUpdateComp1UsingPtr.Filter: TECSFilter;
begin
  Result := world.Filter.Include<TComp1>
end;

procedure TUpdateComp1UsingPtr.Process(e: TECSEntity);
var
  c: ^TComp1;
begin
  c := e.GetPtr<TComp1>;
  c.x := -c.x;
  c.y := -c.y;
end;

{ TReplaceComp1 }

function TReplaceComp1.Filter: TECSFilter;
begin
  Result := world.Filter.Include<TComp1>
end;

procedure TReplaceComp1.Process(e: TECSEntity);
var
  c: TComp1;
begin
  c := e.Get<TComp1>;
  e.Add<TComp5>(TComp5.Create(-c.x, -c.y));
  e.Remove<TComp1>;
end;

{ TReplaceComp5 }

function TReplaceComp5.Filter: TECSFilter;
begin
  Result := world.Filter.Include<TComp5>
end;

procedure TReplaceComp5.Process(e: TECSEntity);
var
  c: TComp5;
begin
  c := e.Get<TComp5>;
  e.Add<TComp1>(TComp1.Create(-c.vx, -c.vy));
  e.Remove<TComp5>;
end;

{ TReplaceComps }

constructor TReplaceComps.Create(AOwner: TECSWorld);
begin
  inherited;
  Add(TReplaceComp1);
  Add(TReplaceComp5);
end;

{ TComplexFilter }

procedure TComplexFilter.Execute;
begin
//  writeln(count);
  count := 0;
end;

function TComplexFilter.Filter: TECSFilter;
begin
  Result := world.Filter.Include<TComp1>.Include<TComp2>.Exclude<TComp3>.
    Exclude<TComp4>
end;

procedure TComplexFilter.Process(e: TECSEntity);
begin
  Inc(count);
end;

begin
  watch := TStopwatch.Create;

end.
