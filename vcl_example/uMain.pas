unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, ecs, Math,  System.Diagnostics,
  Vcl.Mask;

type
  TForm1 = class(TForm)
    PaintBox1: TPaintBox;
    Panel1: TPanel;
    Button1: TButton;
    Timer1: TTimer;
    Label1: TLabel;
    Label2: TLabel;
    LabeledEdit1: TLabeledEdit;
    procedure PaintBox1Paint(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;
  GameWorld: TECSWorld;
  Systems: TECSSystems;
  watch: TStopwatch;

implementation

{$R *.dfm}


type
  TPosition = record
    v : TPoint;
    constructor Create(x, y: Integer);
  end;

  TSpeed = record
    v : TPoint;
    constructor Create(x, y: Integer);
  end;

  TFloating = record
  end;


  TMoveSystem = class(TECSSystem)
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
  end;

  TReflectSystem = class(TECSSystem)
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
  end;

  TGravitySystem = class(TECSSystem)
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
  end;

  TDampingSystem = class(TECSSystem)
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
  end;

  
procedure TForm1.Button1Click(Sender: TObject);
var
  i: Integer;
  ent : TECSEntity;
  n: Integer;
begin
  n := StrToInt(LabeledEdit1.Text);
  GameWorld := TECSWorld.Create;
  for i := 1 to n do
  begin
    ent := GameWorld.NewEntity;
    ent.Add<TPosition>(TPosition.Create(100+random(Form1.PaintBox1.Width-200), 100+random(Form1.PaintBox1.Height-200)));
    case random(3) of
      0: ent.Add<TColor>(clBlack);
      1: begin
          ent.Add<TSpeed>(TSpeed.Create(random(7)-3, random(7)-3));
          ent.Add<TColor>(clRed);
         end;
      2: begin
          ent.Add<TSpeed>(TSpeed.Create(random(7)-3, random(7)-3));
          ent.Add<TColor>(clBlue);
          ent.Add<TFloating>
         end;
    end;
  end;
  Systems := TECSSystems.Create(GameWorld);
  Systems.Add(TMoveSystem.Create(GameWorld));
  Systems.Add(TReflectSystem.Create(GameWorld));
  Systems.Add(TGravitySystem.Create(GameWorld));
  Systems.Add(TDampingSystem.Create(GameWorld));
  Systems.Init;
end;

procedure TForm1.PaintBox1Paint(Sender: TObject);
var
  ent : TECSEntity;
  pos: TPoint;
  speed: TSpeed;
begin
  if not Assigned(GameWorld) then
    exit;
  PaintBox1.Canvas.Brush.Color:=clWhite;
  PaintBox1.Canvas.FillRect(ClientRect);
  for ent in GameWorld.Query<TPosition> do
  begin
    pos := ent.Get<TPosition>.v;
    PaintBox1.Canvas.Pen.Color := ent.Get<TColor>;
    PaintBox1.Canvas.Ellipse(pos.X-2, pos.y-2, pos.X+2, pos.Y+2);
    if ent.TryGet<TSpeed>(speed) then
    begin
      PaintBox1.Canvas.MoveTo(pos.X, pos.Y);
      PaintBox1.Canvas.LineTo(pos.X + speed.v.x*2, pos.Y + speed.v.y*2);
    end;

  end;
end;

procedure TForm1.Timer1Timer(Sender: TObject);
var
  systems_ms, paint_ms: Integer;
begin
  if not Assigned(GameWorld) then exit;
  watch.Reset;
  watch.Start;
  Systems.Execute;
  watch.Stop;
  systems_ms := watch.ElapsedMilliseconds;
  label1.Caption := 'Processing: '+IntToStr(systems_ms)+' ms';

  watch.Reset;
  watch.Start;
  PaintBox1.Repaint;
  watch.Stop;
  paint_ms := watch.ElapsedMilliseconds;
  label2.Caption := 'Render: '+IntToStr(paint_ms)+' ms';
end;

{ TPosition }

constructor TPosition.Create(x, y: Integer);
begin
  v.X := x;
  v.Y := y;
end;

{ TSpeed }

constructor TSpeed.Create(x, y: Integer);
begin
  v.X := x;
  v.Y := y;
end;

{ TMoveSystem }

function TMoveSystem.Filter: TECSFilter;
begin
  Result := World.Filter.Include<TPosition>.Include<TSpeed>;
end;

procedure TMoveSystem.Process(e: TECSEntity);
var
  pos: ^TPosition;
  speed: TSpeed;
begin
  pos := e.GetPtr<TPosition>;
  speed := e.Get<TSpeed>;
  pos.v := pos.v + speed.v;
end;

{ TReflectSystem }

function TReflectSystem.Filter: TECSFilter;
begin
  Result := World.Filter.Include<TPosition>.Include<TSpeed>;
end;

procedure TReflectSystem.Process(e: TECSEntity);
var
  pos: TPosition;
  speed: ^TSpeed;
begin
  pos := e.Get<TPosition>;
  speed := e.GetPtr<TSpeed>;
  if (pos.v.x < 10) and (speed.v.x < 0) then
    speed.v.x := abs(speed.v.x)
  else if (pos.v.x > Form1.PaintBox1.Width-10) and (speed.v.X > 0) then
    speed.v.x := -abs(speed.v.x);
  if (pos.v.y < 10) and (speed.v.y < 0) then
    speed.v.y := abs(speed.v.y)
  else if (pos.v.y > Form1.PaintBox1.Height-10) and (speed.v.Y > 0) then
    speed.v.y := -abs(speed.v.y);

end;

{ TGravitySystem }

function TGravitySystem.Filter: TECSFilter;
begin
  Result := World.Filter.Include<TSpeed>.Exclude<TFloating>;
end;

procedure TGravitySystem.Process(e: TECSEntity);
var
  speed: ^TSpeed;
begin
  if random < 0.9 then
    exit;
  speed := e.GetPtr<TSpeed>;
  speed.v.Y := speed.v.Y + 1;
end;

{ TDampingSystem }

function TDampingSystem.Filter: TECSFilter;
begin
  Result := World.Filter.Include<TSpeed>.Exclude<TFloating>;
end;

procedure TDampingSystem.Process(e: TECSEntity);
var
  speed: ^TSpeed;
begin
  if random < 0.9 then
    exit;
  speed := e.GetPtr<TSpeed>;
  speed.v.Y := speed.v.Y - sign(speed.v.Y);
  speed.v.X := speed.v.X - sign(speed.v.X);
end;

end.
