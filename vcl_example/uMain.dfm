object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Form1'
  ClientHeight = 425
  ClientWidth = 780
  Color = clBtnFace
  DoubleBuffered = True
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  TextHeight = 15
  object PaintBox1: TPaintBox
    Left = 137
    Top = 0
    Width = 643
    Height = 425
    Align = alClient
    OnPaint = PaintBox1Paint
    ExplicitLeft = 119
    ExplicitWidth = 748
    ExplicitHeight = 564
  end
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 137
    Height = 425
    Align = alLeft
    TabOrder = 0
    ExplicitHeight = 424
    object Label1: TLabel
      Left = 8
      Top = 91
      Width = 34
      Height = 15
      Caption = 'Label1'
    end
    object Label2: TLabel
      Left = 8
      Top = 112
      Width = 34
      Height = 15
      Caption = 'Label2'
    end
    object Button1: TButton
      Left = 8
      Top = 56
      Width = 75
      Height = 25
      Caption = 'Init'
      TabOrder = 0
      OnClick = Button1Click
    end
    object LabeledEdit1: TLabeledEdit
      Left = 10
      Top = 27
      Width = 121
      Height = 23
      EditLabel.Width = 41
      EditLabel.Height = 15
      EditLabel.Caption = 'Entities:'
      TabOrder = 1
      Text = '2000'
    end
    object CheckBox1: TCheckBox
      Left = 16
      Top = 152
      Width = 97
      Height = 17
      Caption = 'Fast render'
      TabOrder = 2
    end
  end
  object Timer1: TTimer
    Interval = 50
    OnTimer = Timer1Timer
    Left = 48
    Top = 304
  end
end
