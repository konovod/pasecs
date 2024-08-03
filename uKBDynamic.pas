{-------------------------------------------------------------------------------
 Unit Name: uKBDynamic
 Author:    Krystian Bigaj
 Date:      02-10-2010
 License:   MPL 1.1/GPL 2.0/LGPL 3.0
 EMail:     krystian.bigaj@gmail.com
 WWW:       http://code.google.com/p/kblib/

 Tested on Delphi 2006/2009/XE/XE4/XE5(x64 and x86).

 See TestuKBDynamic.pas and Demos for some examples of usage.

 Notes:
  - Streams are not fully compatible DU* vs. DNU*
    (only if you are using AnsiString).
  - If you care about stream compatibility (DU vs. DNU),
    as String type use always UnicodeString (for DNU it's defined as WideString).
    If you don't need Unicode then use AnsiString.
  - In DNU CodePage for AnsiString is stored as Windows.GetACP
    (it should be System.DefaultSystemCodePage, but I cannot get this under D2006).
    CodePage currently is not used in DNU at all. It's only to make binary
    stream compatible DN vs. DNU. It will probably change in future.
  - In DU CodePage for AnsiString is used as is should be.
  - To speed-up writing to stream, APreAllocSize is by default set to True.
  - For obvious reason, any pointers or pointer types
    are stored directly as in memory (like Pointer, PAnsiChar, TForm, etc.)
  - Because streams are stored as binary, after change in any type you must provide
    version compatibility. If TKBDynamic.ReadFrom returns False, then
    expected version AVersion doesn't match with one stored in stream.
    See Demos\RecordVersions for more details.
  - Don't store interfaces in types, because you will get exception.
    In future there is a plan to add (or use generic one) interface type
    with Load/Save methods. So any interface that implements that one
    could be added to for example to record with store/restore functionality.
  - Don't store Variant type, you will get an exception
    This could be handled in future (for of course only simple types)
  - ReadFrom can raise exceptions for example in case of invalid stream
    or in out of memory condition
  - Streams are not compatible between x64 and x86 unless you use kdoCPUArchCompatibility
    and provide additional compatibility (read comments on kdoCPUArchCompatibility)
  * DU - Delphi Unicode (Delphi D2009+)
  * DNU - Delphi non-Unicode (older than D2009)

-------------------------------------------------------------------------------}

unit uKBDynamic;

interface

uses
  SysUtils, Classes, TypInfo, RTLConsts;

type

{ Compiler compatibility }

  // XE4+ legacy warning silence
  {$IF CompilerVersion >= 25}
  {$LEGACYIFEND on}
  {$IFEND}

  // D2009 and older. D2007/D2009 supports NativeInt/NativeUInt, however compiler is buggy for this types.
  // http://qc.embarcadero.com/wc/qcmain.aspx?d=71292
  {$IF CompilerVersion < 21}
  NativeInt = Integer;
  NativeUInt = Cardinal;
  PNativeInt = ^NativeInt;
  PNativeUInt = ^NativeUInt;
  {$IFEND}

  KBSize = NativeInt;

  PKBPointerMath = ^KBPointerMath;
  KBPointerMath = NativeUInt;

  PKBStrLen = ^KBStrLen;
  KBStrLen = Integer;

  PKBArrayLen = ^KBArrayLen;
  KBArrayLen = NativeInt;

  PKBArrayLen86 = ^KBArrayLen86;
  KBArrayLen86 = KBStrLen;

  {$IF Declared(UnicodeString)}
  KBUnicodeString = UnicodeString;
  {$ELSE}
  KBUnicodeString = WideString;
  {$IFEND}

{ TKBDynamicOption }

  TKBDynamicOption = (
    kdoAnsiStringCodePage,    // Stores CodePage for AnsiString. Adds 2 bytes for each AnsiString.
                              // Only for D2009+. For older versions currently doesn't take any effect.
                              // If you are using non-Unicode delphi and dont care about compatibility
                              // then don't set this option
                              //
                              // Default: On

    kdoUTF16ToUTF8,           // WideString/UnicodeString will be stored as UTF8.
                              // This saves space in output buffer, but a little slower operations (read/write/sizeof).
                              // Useful especially when stream size if important (like transfer streams over internet)
                              //
                              // Default: Off (unless KBDYNAMIC_DEFAULT_UTF8 is defined)

    kdoLimitToWordSize,       // Limits strings/DynArray sizes to Word (65535).
                              // If it exceeds limit then exception EKBDynamicWordLimit is raised
                              // Useful especially when stream size if important (like transfer streams over internet)
                              //
                              // Default: Off (unless KBDYNAMIC_DEFAULT_WORDSIZE is defined)

    kdoCPUArchCompatibility   // Allows to share streams between x64 and x86 (SEE NOTES below before usage!)
                              // WARNING: You MUST provide by yourself 'CPU Architecture compatible' records:
                              // - records MUST be defined as 'packed record' !!!
                              // - you cannot use non-dynamic types that have different size depending on architecture,
                              //   so avoid types like: NativeInt, NativeUInt, Extended,
                              //   pointer types of any kind (Pointer, PChar, TObject, ...)
                              // - you cannot use dynamic arrays with more elements than MaxInt (2147483647),
                              //   but this one should not be a problem :)
                              //
                              // Hint: If you saved record with Delphi x86 without kdoCPUArchCompatibility,
                              // and now you want to read that record o x64 then use ReadFrom with
                              // AForceCPUArchCompatibilityOnStreamV1=True - read comments!!!
                              //
                              // If dynamic array exceeds MaxInt limit then exception EKBDynamicLimit is raised.
                              //
                              // If you use kdoLimitToWordSize with kdoCPUArchCompatibility, then
                              // strings/dynamic arrays will be limited to 65535 elements.
                              //
                              // Default: Off (unless KBDYNAMIC_DEFAULT_CPUARCH is defined)
  );

  TKBDynamicOptions = set of TKBDynamicOption;

const
  // Default options set
  TKBDynamicDefaultOptions = [
    kdoAnsiStringCodePage

    {$IFDEF KBDYNAMIC_DEFAULT_UTF8}
    ,kdoUTF16ToUTF8
    {$ENDIF}

    {$IFDEF KBDYNAMIC_DEFAULT_WORDSIZE}
    ,kdoLimitToWordSize
    {$ENDIF}

    {$IFDEF KBDYNAMIC_DEFAULT_CPUARCH}
    ,kdoCPUArchCompatibility
    {$ENDIF}
  ];

  // Useful options set for transferring streams over internet (safe)
  TKBDynamicNetworkSafeOptions = [
    kdoAnsiStringCodePage,
    kdoUTF16ToUTF8
  ];

  // Useful options set for transferring streams over internet (less space, but unsafe in some cases)
  // Use less space than TKBDynamicNetworkSafeOptions, but:
  // - kdoAnsiStringCodePage is NOT set, so doesn't store CodePage for AnsiString
  //     2 bytes less for each AnsiString
  // - kdoLimitToWordSize is set, so Strings/DynArray size is limited to 65535 elements
  //     2 bytes less for each String/AnsiString/WideString/DynArray)
  TKBDynamicNetworkUnsafeOptions = [
    kdoUTF16ToUTF8,
    kdoLimitToWordSize
  ];

type

{ EKBDynamic }

  EKBDynamic = class(Exception);

{ EKBDynamicInvalidType }

  EKBDynamicInvalidType = class(EKBDynamic)
  private
    FTypeKind: TTypeKind;
  public
    constructor Create(ATypeKind: TTypeKind);

    property TypeKind: TTypeKind read FTypeKind;
  end;

{ EKBDynamicLimit }

  EKBDynamicLimit = class(EKBDynamic)
  public
    constructor Create(ALen, AMaxLen: KBArrayLen); reintroduce;
  end;

{ EKBDynamicWordLimit }

  EKBDynamicWordLimit = class(EKBDynamicLimit)
  public
    constructor Create(ALen: KBArrayLen); reintroduce;
  end;

{ TKBDynamic }

  TKBDynamic = class
    class function Compare(const ADynamicType1, ADynamicType2;
      ATypeInfo: PTypeInfo): Boolean;

    class function GetSize(const ADynamicType; ATypeInfo: PTypeInfo;
      const AOptions: TKBDynamicOptions = TKBDynamicDefaultOptions): KBSize;

    class procedure WriteTo(AStream: TStream; const ADynamicType;
      ATypeInfo: PTypeInfo; AVersion: Word = 1;
      const AOptions: TKBDynamicOptions = TKBDynamicDefaultOptions;
      APreAllocSize: Boolean = True);

    // ReadFrom: Set AForceCPUArchCompatibilityOnStreamV1=True, when you need to read
    // stream created with Delphi x86 compiler (like saved on disk or in DB),
    // but you haven't used used latest TKBDynamic with kdoCPUArchCompatibility support.
    // However, you MUST make your record as 'packed record' and make all
    // non-dynamic fields same size as default non-packed 'record' on x86.
    //
    // For example if you saved record on x86:
    //
    //    TMyRecord = record
    //      SomeSwitch: Boolean; // on x86 it will use 4 bytes, so you need to make 3 bytes padding when using 'packed record'
    //      SomeByte: Byte;      // on x86 it will use 4 bytes, so you need to make 3 bytes padding when using 'packed record'
    //      SomeWord: Word;      // on x86 it will use 4 bytes, so you need to make 2 bytes padding when using 'packed record'
    //      Str: String;
    //    end;
    //
    // and now you want to read that record on x64 then set AForceCPUArchCompatibilityOnStreamV1=True,
    // but define record as (on x64, and if you want also on x86):
    //
    //    TMyRecord = packed record   // record must be 'packed'
    //      SomeSwitch: Boolean;
    //      _SomeSwitch_Pading: array[0..2] of Byte;  // 3 bytes of padding, to make field size same on x64 and x86 with 'packed record'
    //
    //      SomeByte: Byte;
    //      _SomeByte_Pading: array[0..2] of Byte;    // 3 bytes of padding, to make field size same on x64 and x86 with 'packed record'
    //
    //      SomeWord: Word;
    //      _SomeWord_Pading: array[0..1] of Byte;    // 2 bytes of padding, to make field size same on x64 and x86 with 'packed record'
    //      Str: String;
    //    end;
    class function ReadFrom(AStream: TStream; const ADynamicType;
      ATypeInfo: PTypeInfo; AVersion: Word = 1;
      AForceCPUArchCompatibilityOnStreamV1: Boolean = False): Boolean;

    // "No Header" version of methods
    // (4 bytes less, but you need take care of of version/compatibility and options)

    class function GetSizeNH(const ADynamicType; ATypeInfo: PTypeInfo;
      const AOptions: TKBDynamicOptions = TKBDynamicDefaultOptions): KBSize;

    class procedure WriteToNH(AStream: TStream; const ADynamicType;
      ATypeInfo: PTypeInfo;
      const AOptions: TKBDynamicOptions = TKBDynamicDefaultOptions);

    class procedure ReadFromNH(AStream: TStream; const ADynamicType;
      ATypeInfo: PTypeInfo;
      const AOptions: TKBDynamicOptions = TKBDynamicDefaultOptions);
  end;

{ TKBDynamicHeader }

  TKBDynamicHeader = packed record
    Stream: record
      Version: Byte;
      Options: Byte;
    end;
    TypeVersion: Word;
  end;

// -----------------------------------------------------------------------------
// --- Config header options
// -----------------------------------------------------------------------------

const
  // Version (1 Byte)
  cKBDYNAMIC_STREAM_VERSION_v1              = $01; // Arch: Little Endian, 32 bit, used also on x64 with kdoCPUArchCompatibility
  cKBDYNAMIC_STREAM_VERSION_v2              = $02; // Arch: Little Endian, 64 bit

  // CFG (1 Byte)
  cKBDYNAMIC_STREAM_CFG_UNICODE             = $01;  // Stream created in UNICODE version of delphi (D2009+),
                                                    // older versions doesn't support UnicodeString type,
                                                    // and CodePage for AnsiString/UTF8String

  cKBDYNAMIC_STREAM_CFG_UTF8                = $02;  // kdoUTF16ToUTF8

  cKBDYNAMIC_STREAM_CFG_WORDSIZE            = $04;  // kdoLimitToWordSize

  cKBDYNAMIC_STREAM_CFG_CODEPAGE            = $08;  // kdoAnsiStringCodePage

  cKBDYNAMIC_STREAM_CFG_CPUARCH             = $10;  // kdoCPUArchCompatibility

//cKBDYNAMIC_STREAM_CFG_XXX                 = $20;
//cKBDYNAMIC_STREAM_CFG_XXX                 = $40;
//cKBDYNAMIC_STREAM_CFG_XXX                 = $80;

implementation

{$IF Declared(UnicodeString)}
const
  MAXWORD = 65535;
{$ELSE}
uses
  Windows;
{$IFEND}

// -----------------------------------------------------------------------------
// --- Some RTTI info types (from System.pas)
// -----------------------------------------------------------------------------

type

{ TFieldInfo }

  PPTypeInfo = ^PTypeInfo;
  TFieldInfo = packed record
    TypeInfo: PPTypeInfo;
    Offset: KBPointerMath;
  end;

{ TFieldTable }

  PFieldTable = ^TFieldTable;
  TFieldTable = packed record
    X: Word;
    Size: Cardinal;
    Count: Cardinal;
    Fields: array [0..65535] of TFieldInfo;
  end;

{ TDynArrayTypeInfo }

  PDynArrayTypeInfo = ^TDynArrayTypeInfo;
  TDynArrayTypeInfo = packed record
    kind: Byte;
    name: Byte;
    elSize: KBArrayLen86;
    elType: ^PDynArrayTypeInfo;
    varType: Integer;
  end;

// -----------------------------------------------------------------------------
// --- Compare
// -----------------------------------------------------------------------------

function DynamicCompare_Array(ADynamic1, ADynamic2: Pointer;
  ATypeInfo: PTypeInfo; ALength: KBArrayLen): Boolean; forward;

function DynamicCompare_Record(ADynamic1, ADynamic2: Pointer;
  AFieldTable: PFieldTable): Boolean;
var
  lCompare: KBPointerMath;
  lOffset: KBPointerMath;
  lIdx: KBPointerMath;
  lTypeInfo: PTypeInfo;
begin
  if AFieldTable^.Count = 0 then
  begin
    Result := CompareMem(ADynamic1, ADynamic2, AFieldTable^.Size);
    Exit;
  end;

  Result := False;
  lCompare := 0;
  lIdx := 0;

  while (lCompare < AFieldTable^.Size) and (lIdx < AFieldTable^.Count) do
  begin
    lOffset := AFieldTable^.Fields[lIdx].Offset;

    if lCompare < lOffset then
      if CompareMem(
        Pointer(KBPointerMath(ADynamic1) + lCompare),
        Pointer(KBPointerMath(ADynamic2) + lCompare),
        lOffset - lCompare
      ) then
        Inc(lCompare, lOffset - lCompare)
      else
        Exit;

    lTypeInfo := AFieldTable^.Fields[lIdx].TypeInfo^;

    if DynamicCompare_Array(
      Pointer(KBPointerMath(ADynamic1) + lOffset),
      Pointer(KBPointerMath(ADynamic2) + lOffset),
      lTypeInfo,
      1
    ) then
    begin
      case lTypeInfo^.Kind of
      tkArray, tkRecord:
        Inc(lCompare, PFieldTable(KBPointerMath(lTypeInfo) + PByte(@lTypeInfo^.Name)^)^.Size);
      else
        Inc(lCompare, SizeOf(Pointer));
      end;
    end else
      Exit;

    Inc(lIdx);
  end;

  if lCompare < AFieldTable^.Size then
    if not CompareMem(
      Pointer(KBPointerMath(ADynamic1) + lCompare),
      Pointer(KBPointerMath(ADynamic2) + lCompare),
      AFieldTable^.Size - lCompare
    ) then
      Exit;

  Result := True;
end;

function DynamicCompare_DynArray(ADynamic1, ADynamic2: Pointer;
  ATypeInfo: PTypeInfo): Boolean;
var
  lDyn: PDynArrayTypeInfo;
  lLen, lLen2: KBArrayLen;
begin
  if ADynamic1 = ADynamic2 then
  begin
    Result := True;
    Exit;
  end;

  if PPointer(ADynamic1)^ = nil then
    lLen := 0
  else
    lLen := PKBArrayLen(PKBPointerMath(ADynamic1)^ - SizeOf(KBArrayLen))^;

  if PPointer(ADynamic2)^ = nil then
    lLen2 := 0
  else
    lLen2 := PKBArrayLen(PKBPointerMath(ADynamic2)^ - SizeOf(KBArrayLen))^;

  Result := lLen = lLen2;

  if (not Result) or (lLen = 0) then
    Exit;

  lDyn := PDynArrayTypeInfo(KBPointerMath(ATypeInfo) + PByte(@ATypeInfo^.Name)^);

  if lDyn^.elType = nil then
    Result := CompareMem(PPointer(ADynamic1)^, PPointer(ADynamic2)^, lLen * lDyn^.elSize)
  else
    Result := DynamicCompare_Array(
      PPointer(ADynamic1)^,
      PPointer(ADynamic2)^,
      PTypeInfo(lDyn^.elType^),
      lLen
    );
end;

function DynamicCompare_Array(ADynamic1, ADynamic2: Pointer;
  ATypeInfo: PTypeInfo; ALength: KBArrayLen): Boolean;
var
  lFieldTable: PFieldTable;
begin
  Result := (ALength = 0) or (ADynamic1 = ADynamic2);

  if Result then
    Exit;

  case ATypeInfo^.Kind of
  {$IF Declared(AnsiString)}
  tkLString:
    while ALength > 0 do
    begin
      if ADynamic1 <> ADynamic2 then
        if PAnsiString(ADynamic1)^ <> PAnsiString(ADynamic2)^ then
          Exit;

      Inc(PPointer(ADynamic1));
      Inc(PPointer(ADynamic2));
      Dec(ALength);
    end;
  {$IFEND}

  {$IF Declared(WideString)}
  tkWString:
    while ALength > 0 do
    begin
      if ADynamic1 <> ADynamic2 then
        if PWideString(ADynamic1)^ <> PWideString(ADynamic2)^ then
          Exit;

      Inc(PPointer(ADynamic1));
      Inc(PPointer(ADynamic2));
      Dec(ALength);
    end;
  {$IFEND}

  {$IF Declared(UnicodeString)}
  tkUString:
    while ALength > 0 do
    begin
      if ADynamic1 <> ADynamic2 then
        if PUnicodeString(ADynamic1)^ <> PUnicodeString(ADynamic2)^ then
          Exit;

      Inc(PPointer(ADynamic1));
      Inc(PPointer(ADynamic2));
      Dec(ALength);
    end;
  {$IFEND}

  tkArray:
    begin
      lFieldTable := PFieldTable(KBPointerMath(ATypeInfo) + PByte(@PTypeInfo(ATypeInfo).Name)^);
      while ALength > 0 do
      begin
        if not DynamicCompare_Array(ADynamic1, ADynamic2, lFieldTable.Fields[0].TypeInfo^, lFieldTable.Count) then
          Exit;

        Inc(KBPointerMath(ADynamic1), lFieldTable.Size);
        Inc(KBPointerMath(ADynamic2), lFieldTable.Size);
        Dec(ALength);
      end;
    end;

  tkRecord:
    begin
      lFieldTable := PFieldTable(KBPointerMath(ATypeInfo) + PByte(@PTypeInfo(ATypeInfo).Name)^);
      while ALength > 0 do
      begin
        if not DynamicCompare_Record(ADynamic1, ADynamic2, lFieldTable) then
          Exit;

        Inc(KBPointerMath(ADynamic1), lFieldTable.Size);
        Inc(KBPointerMath(ADynamic2), lFieldTable.Size);
        Dec(ALength);
      end;
    end;

  tkDynArray:
    while ALength > 0 do
    begin
      if not DynamicCompare_DynArray(ADynamic1, ADynamic2, ATypeInfo) then
        Exit;

      Inc(PPointer(ADynamic1));
      Inc(PPointer(ADynamic2));
      Dec(ALength);
    end;
  else
    raise EKBDynamicInvalidType.Create(ATypeInfo^.Kind);
  end;

  Result := True;
end;

// -----------------------------------------------------------------------------
// --- GetSize
// -----------------------------------------------------------------------------

function DynamicGetSize_Array(ADynamic: Pointer; ATypeInfo: PTypeInfo;
  ALength: KBArrayLen; const AOptions: TKBDynamicOptions): KBSize; forward;

function DynamicGetSize_Record(ADynamic: Pointer; AFieldTable: PFieldTable;
  const AOptions: TKBDynamicOptions): KBSize;
var
  lCompare: KBPointerMath;
  lOffset: KBPointerMath;
  lIdx: KBPointerMath;
  lTypeInfo: PTypeInfo;
begin
  if AFieldTable^.Count = 0 then
  begin
    Result := AFieldTable^.Size;
    Exit;
  end;

  lCompare := 0;
  lIdx := 0;
  Result := 0;

  while (lCompare < AFieldTable^.Size) and (lIdx < AFieldTable^.Count) do
  begin
    lOffset := AFieldTable^.Fields[lIdx].Offset;

    if lCompare < lOffset then
    begin
      Inc(Result, lOffset - lCompare);

      Inc(lCompare, lOffset - lCompare)
    end;

    lTypeInfo := AFieldTable^.Fields[lIdx].TypeInfo^;

    Inc(Result, DynamicGetSize_Array(
      Pointer(KBPointerMath(ADynamic) + lOffset),
      lTypeInfo,
      1,
      AOptions
    ));

    case lTypeInfo^.Kind of
    tkArray, tkRecord:
      Inc(lCompare, PFieldTable(KBPointerMath(lTypeInfo) + PByte(@lTypeInfo^.Name)^)^.Size);
    else
      Inc(lCompare, SizeOf(Pointer));
    end;

    Inc(lIdx);
  end;

  if lCompare < AFieldTable^.Size then
    Inc(Result, AFieldTable^.Size - lCompare);
end;

function DynamicGetSize_DynArray(ADynamic: Pointer; ATypeInfo: PTypeInfo;
  const AOptions: TKBDynamicOptions): KBSize;
var
  lDyn: PDynArrayTypeInfo;
  lLen: KBArrayLen;
begin
  if kdoLimitToWordSize in AOptions then
    Result := SizeOf(Word)
  else
    if kdoCPUArchCompatibility in AOptions then
      Result := SizeOf(KBArrayLen86)
    else
      Result := SizeOf(KBArrayLen); // dynamic array length

  if PPointer(ADynamic)^ = nil then
    Exit;

  lLen := PKBArrayLen(PKBPointerMath(ADynamic)^ - SizeOf(KBArrayLen))^;

  if (kdoLimitToWordSize in AOptions) and (lLen > MAXWORD) then
    raise EKBDynamicWordLimit.Create(lLen);

  {$IFDEF CPUX64}
  if (kdoCPUArchCompatibility in AOptions) and (lLen > MaxInt) then
    raise EKBDynamicLimit.Create(lLen, MaxInt);
  {$ENDIF}

  lDyn := PDynArrayTypeInfo(KBPointerMath(ATypeInfo) + PByte(@ATypeInfo^.Name)^);

  if lDyn^.elType = nil then
    Inc(Result, lLen * lDyn^.elSize)
  else
    Inc(Result, DynamicGetSize_Array(
      PPointer(ADynamic)^,
      PTypeInfo(lDyn^.elType^),
      lLen,
      AOptions
    ));
end;

function DynamicGetSize_Array(ADynamic: Pointer; ATypeInfo: PTypeInfo;
  ALength: KBArrayLen; const AOptions: TKBDynamicOptions): KBSize;
var
  lFieldTable: PFieldTable;
  lStrLen: KBStrLen;
begin
  Result := 0;

  if ALength = 0 then
    Exit;


  case ATypeInfo^.Kind of
  {$IF Declared(AnsiString)}
  tkLString:
    while ALength > 0 do
    begin
      if kdoLimitToWordSize in AOptions then
        Inc(Result, SizeOf(Word))  // string length limited
      else
        Inc(Result, SizeOf(KBStrLen)); // string length

      if PPointer(ADynamic)^ <> nil then
      begin
        lStrLen := Length(PAnsiString(ADynamic)^);

        if lStrLen > 0 then
        begin
          if (kdoLimitToWordSize in AOptions) and (lStrLen > MAXWORD) then
            raise EKBDynamicWordLimit.Create(lStrLen);

          Inc(Result, lStrLen * SizeOf(AnsiChar));
          if kdoAnsiStringCodePage in AOptions then
            Inc(Result, SizeOf(Word) {CodePage});
        end;
      end;

      Inc(PPointer(ADynamic));
      Dec(ALength);
    end;
  {$IFEND}

  {$IF Declared(WideString)}
  tkWString:
    while ALength > 0 do
    begin
      if kdoLimitToWordSize in AOptions then
        Inc(Result, SizeOf(Word))  // string length limited
      else
        Inc(Result, SizeOf(KBStrLen)); // string length

      if PPointer(ADynamic)^ <> nil then
      begin
        lStrLen := Length(PWideString(ADynamic)^);

        if lStrLen > 0 then
        begin
          if kdoUTF16ToUTF8 in AOptions then
          begin
            lStrLen := UnicodeToUtf8(nil, MaxInt, PWideChar(ADynamic^), lStrLen);

            if lStrLen = 0 then
              raise EKBDynamic.Create('UnicodeToUtf8 failed!');
          end;

          if (kdoLimitToWordSize in AOptions) and (lStrLen > MAXWORD) then
            raise EKBDynamicWordLimit.Create(lStrLen);

          if kdoUTF16ToUTF8 in AOptions then
            Inc(Result, lStrLen)
          else
            Inc(Result, lStrLen * SizeOf(WideChar));
        end;
      end;

      Inc(PPointer(ADynamic));
      Dec(ALength);
    end;
  {$IFEND}

  {$IF Declared(UnicodeString)}
  tkUString:
    while ALength > 0 do
    begin
      if kdoLimitToWordSize in AOptions then
        Inc(Result, SizeOf(Word))  // string length limited
      else
        Inc(Result, SizeOf(KBStrLen)); // string length

      if PPointer(ADynamic)^ <> nil then
      begin
        lStrLen := Length(PUnicodeString(ADynamic)^);

        if lStrLen > 0 then
        begin
          if kdoUTF16ToUTF8 in AOptions then
          begin
            lStrLen := UnicodeToUtf8(nil, MaxInt, PWideChar(ADynamic^), lStrLen);

            if lStrLen = 0 then
              raise EKBDynamic.Create('UnicodeToUtf8 failed!');
          end;

          if (kdoLimitToWordSize in AOptions) and (lStrLen > MAXWORD) then
            raise EKBDynamicWordLimit.Create(lStrLen);

          if kdoUTF16ToUTF8 in AOptions then
            Inc(Result, lStrLen)
          else
            Inc(Result, lStrLen * SizeOf(WideChar));
        end;
      end;

      Inc(PPointer(ADynamic));
      Dec(ALength);
    end;
  {$IFEND}

  tkArray:
    begin
      lFieldTable := PFieldTable(KBPointerMath(ATypeInfo) + PByte(@PTypeInfo(ATypeInfo).Name)^);
      while ALength > 0 do
      begin
        Inc(Result, DynamicGetSize_Array(
          ADynamic,
          lFieldTable.Fields[0].TypeInfo^,
          lFieldTable.Count,
          AOptions
        ));

        Inc(KBPointerMath(ADynamic), lFieldTable.Size);
        Dec(ALength);
      end;
    end;

  tkRecord:
    begin
      lFieldTable := PFieldTable(KBPointerMath(ATypeInfo) + PByte(@PTypeInfo(ATypeInfo).Name)^);
      while ALength > 0 do
      begin
        Inc(Result, DynamicGetSize_Record(ADynamic, lFieldTable, AOptions));
        Inc(KBPointerMath(ADynamic), lFieldTable.Size);
        Dec(ALength);
      end;
    end;

  tkDynArray:
    while ALength > 0 do
    begin
      Inc(Result, DynamicGetSize_DynArray(ADynamic, ATypeInfo, AOptions));
      Inc(KBPointerMath(ADynamic), SizeOf(Pointer));
      Dec(ALength);
    end;
  else
    raise EKBDynamicInvalidType.Create(ATypeInfo^.Kind);
  end;
end;

// -----------------------------------------------------------------------------
// --- Write
// -----------------------------------------------------------------------------

procedure TStream_WriteBuffer(AStream: TStream; var ABuffer; ACount: Integer);
begin
  // Workaround: Delphi XE3/XE4 have some performance issue in TStream.ReadBuffer/WriteBuffer
  if (ACount <> 0) and (AStream.Write(ABuffer, ACount) <> ACount) then
    raise EWriteError.CreateRes(@SWriteError);
end;

procedure DynamicWrite_Array(AStream: TStream; ADynamic: Pointer;
  ATypeInfo: PTypeInfo; ALength: KBArrayLen; const AOptions: TKBDynamicOptions); forward;

procedure DynamicWrite_Record(AStream: TStream; ADynamic: Pointer;
  AFieldTable: PFieldTable; const AOptions: TKBDynamicOptions);
var
  lCompare: KBPointerMath;
  lOffset: KBPointerMath;
  lIdx: KBPointerMath;
  lTypeInfo: PTypeInfo;
begin
  if AFieldTable^.Count = 0 then
  begin
    TStream_WriteBuffer(AStream, PByte(ADynamic)^, AFieldTable.Size);
    Exit;
  end;

  lCompare := 0;
  lIdx := 0;

  while (lCompare < AFieldTable^.Size) and (lIdx < AFieldTable^.Count) do
  begin
    lOffset := AFieldTable^.Fields[lIdx].Offset;

    if lCompare < lOffset then
    begin
      TStream_WriteBuffer(AStream, PByte((KBPointerMath(ADynamic) + lCompare))^, lOffset - lCompare);

      Inc(lCompare, lOffset - lCompare);
    end;

    lTypeInfo := AFieldTable^.Fields[lIdx].TypeInfo^;

    DynamicWrite_Array(
      AStream,
      Pointer(KBPointerMath(ADynamic) + lOffset),
      lTypeInfo,
      1,
      AOptions
    );

    case lTypeInfo^.Kind of
    tkArray, tkRecord:
      Inc(lCompare, PFieldTable(KBPointerMath(lTypeInfo) + PByte(@lTypeInfo^.Name)^)^.Size);
    else
      Inc(lCompare, SizeOf(Pointer));
    end;

    Inc(lIdx);
  end;

  if lCompare < AFieldTable^.Size then
    TStream_WriteBuffer(AStream, PByte(KBPointerMath(ADynamic) + lCompare)^, AFieldTable^.Size - lCompare);
end;

procedure DynamicWrite_DynArray(AStream: TStream; ADynamic: Pointer;
  ATypeInfo: PTypeInfo; const AOptions: TKBDynamicOptions);
var
  lDyn: PDynArrayTypeInfo;
  lLen: KBArrayLen;
begin
  if PPointer(ADynamic)^ = nil then
    lLen := 0
  else
    lLen := PKBArrayLen(PKBPointerMath(ADynamic)^ - SizeOf(KBArrayLen))^;

  if kdoLimitToWordSize in AOptions then
  begin
    if lLen > MAXWORD then
      raise EKBDynamicWordLimit.Create(lLen);

    TStream_WriteBuffer(AStream, lLen, SizeOf(Word));
  end else
    if kdoCPUArchCompatibility in AOptions then
    begin
      {$IFDEF CPUX64}
      if lLen > MaxInt then
        raise EKBDynamicLimit.Create(lLen, MaxInt);
      {$ENDIF}

      TStream_WriteBuffer(AStream, lLen, SizeOf(KBArrayLen86));
    end else
      TStream_WriteBuffer(AStream, lLen, SizeOf(KBArrayLen));

  if lLen = 0 then
    Exit;

  lDyn := PDynArrayTypeInfo(KBPointerMath(ATypeInfo) + PByte(@ATypeInfo^.Name)^);

  if lDyn^.elType = nil then
    TStream_WriteBuffer(AStream, PByte(ADynamic^)^, lLen * lDyn^.elSize)
  else
    DynamicWrite_Array(
      AStream,
      PPointer(ADynamic)^,
      PTypeInfo(lDyn^.elType^),
      lLen,
      AOptions
    );
end;

procedure DynamicWrite_UTF16AsUFT8(AStream: TStream; APWideChar: PPWideChar;
  ALen: KBStrLen; const AOptions: TKBDynamicOptions);
var
  lUTF8: Pointer;
  lStrLen: KBStrLen;
begin
  if ALen = 0 then
  begin
    if kdoLimitToWordSize in AOptions then
      TStream_WriteBuffer(AStream, ALen, SizeOf(Word))
    else
      TStream_WriteBuffer(AStream, ALen, SizeOf(KBStrLen));

    Exit;
  end;

  lStrLen := UnicodeToUtf8(nil, MaxInt, APWideChar^, ALen);
  if lStrLen = 0 then
    raise EKBDynamic.Create('UnicodeToUtf8 failed!');

  GetMem(lUTF8, lStrLen + 1);
  if UnicodeToUtf8(lUTF8, lStrLen + 1, APWideChar^, ALen) <> Cardinal(lStrLen + 1) then
  begin
    FreeMem(lUTF8);
    raise EKBDynamic.Create('UnicodeToUtf8 failed!');
  end;

  if kdoLimitToWordSize in AOptions then
  begin
    if lStrLen > MAXWORD then
    begin
      FreeMem(lUTF8);
      raise EKBDynamicWordLimit.Create(lStrLen);
    end;

    if AStream.Write(lStrLen, SizeOf(Word)) <> SizeOf(Word) then
    begin
      FreeMem(lUTF8);
      raise EWriteError.CreateRes(@SWriteError);
    end;
  end else
    if AStream.Write(lStrLen, SizeOf(KBStrLen)) <> SizeOf(KBStrLen) then
    begin
      FreeMem(lUTF8);
      raise EWriteError.CreateRes(@SWriteError);
    end;

  if AStream.Write(lUTF8^, lStrLen) <> lStrLen then
  begin
    FreeMem(lUTF8);
    raise EWriteError.CreateRes(@SWriteError);
  end;

  FreeMem(lUTF8);
end;

procedure DynamicWrite_Array(AStream: TStream; ADynamic: Pointer;
  ATypeInfo: PTypeInfo; ALength: KBArrayLen; const AOptions: TKBDynamicOptions);
var
  lFieldTable: PFieldTable;
  lStrLen: KBStrLen;
  {$IF Declared(AnsiString)}
  lCP: Word;
  {$IFEND}
begin
  if ALength = 0 then
    Exit;

  case ATypeInfo^.Kind of
  {$IF Declared(AnsiString)}
  tkLString:
    while ALength > 0 do
    begin
      if PPointer(ADynamic)^ = nil then
        lStrLen := 0
      else
        lStrLen := Length(PAnsiString(ADynamic)^);

      if kdoLimitToWordSize in AOptions then
      begin
        if lStrLen > MAXWORD then
          raise EKBDynamicWordLimit.Create(lStrLen);

        TStream_WriteBuffer(AStream, lStrLen, SizeOf(Word));
      end else
        TStream_WriteBuffer(AStream, lStrLen, SizeOf(KBStrLen));

      if lStrLen > 0 then
      begin
        TStream_WriteBuffer(AStream, PByte(ADynamic^)^, lStrLen * SizeOf(AnsiChar));

        if kdoAnsiStringCodePage in AOptions then
        begin
          {$IF Declared(UnicodeString)}
          lCP := PWord(PKBPointerMath(ADynamic)^ - 12)^; // StrRec.codePage
          {$ELSE}
          lCP := GetACP; // TODO: System.DefaultSystemCodePage
          {$IFEND}

          TStream_WriteBuffer(AStream, lCP, SizeOf(Word));
        end;
      end;

      Inc(PPointer(ADynamic));
      Dec(ALength);
    end;
  {$IFEND}

  {$IF Declared(WideString)}
  tkWString:
    while ALength > 0 do
    begin
      if PPointer(ADynamic)^ = nil then
        lStrLen := 0
      else
        lStrLen := Length(PWideString(ADynamic)^);

      if kdoUTF16ToUTF8 in AOptions then
        DynamicWrite_UTF16AsUFT8(AStream, ADynamic, lStrLen, AOptions)
      else
      begin
        if kdoLimitToWordSize in AOptions then
        begin
          if lStrLen > MAXWORD then
            raise EKBDynamicWordLimit.Create(lStrLen);

          TStream_WriteBuffer(AStream, lStrLen, SizeOf(Word));
        end else
          TStream_WriteBuffer(AStream, lStrLen, SizeOf(KBStrLen));

        if lStrLen > 0 then
          TStream_WriteBuffer(AStream, PByte(ADynamic^)^, lStrLen * SizeOf(WideChar));
      end;

      Inc(PPointer(ADynamic));
      Dec(ALength);
    end;
  {$IFEND}

  {$IF Declared(UnicodeString)}
  tkUString:
    while ALength > 0 do
    begin
      if PPointer(ADynamic)^ = nil then
        lStrLen := 0
      else
        lStrLen := Length(PUnicodeString(ADynamic)^);

      if kdoUTF16ToUTF8 in AOptions then
        DynamicWrite_UTF16AsUFT8(AStream, ADynamic, lStrLen, AOptions)
      else
      begin
        if kdoLimitToWordSize in AOptions then
        begin
          if lStrLen > MAXWORD then
            raise EKBDynamicWordLimit.Create(lStrLen);

          TStream_WriteBuffer(AStream, lStrLen, SizeOf(Word));
        end else
          TStream_WriteBuffer(AStream, lStrLen, SizeOf(KBStrLen));

        if lStrLen > 0 then
          TStream_WriteBuffer(AStream, PByte(ADynamic^)^, lStrLen * SizeOf(WideChar));
      end;

      Inc(PPointer(ADynamic));
      Dec(ALength);
    end;
  {$IFEND}

  tkArray:
    begin
      lFieldTable := PFieldTable(KBPointerMath(ATypeInfo) + PByte(@PTypeInfo(ATypeInfo).Name)^);
      while ALength > 0 do
      begin
        DynamicWrite_Array(AStream, ADynamic, lFieldTable.Fields[0].TypeInfo^,
          lFieldTable.Count, AOptions);
        Inc(KBPointerMath(ADynamic), lFieldTable.Size);
        Dec(ALength);
      end;
    end;

  tkRecord:
    begin
      lFieldTable := PFieldTable(KBPointerMath(ATypeInfo) + PByte(@PTypeInfo(ATypeInfo).Name)^);
      while ALength > 0 do
      begin
        DynamicWrite_Record(AStream, ADynamic, lFieldTable, AOptions);
        Inc(KBPointerMath(ADynamic), lFieldTable.Size);
        Dec(ALength);
      end;
    end;

  tkDynArray:
    while ALength > 0 do
    begin
      DynamicWrite_DynArray(AStream, ADynamic, ATypeInfo, AOptions);
      Inc(KBPointerMath(ADynamic), SizeOf(Pointer));
      Dec(ALength);
    end;
  else
    raise EKBDynamicInvalidType.Create(ATypeInfo^.Kind);
  end;
end;

// -----------------------------------------------------------------------------
// --- Read
// -----------------------------------------------------------------------------

procedure TStream_ReadBuffer(AStream: TStream; var ABuffer; ACount: Integer);
begin
  // Workaround: Delphi XE3/XE4 have some performance issue in TStream.ReadBuffer/WriteBuffer
  if (ACount <> 0) and (AStream.Read(ABuffer, ACount) <> ACount) then
    raise EReadError.CreateRes(@SReadError);
end;

procedure DynamicRead_Array(AStream: TStream; ADynamic: Pointer;
  ATypeInfo: PTypeInfo; ALength: KBArrayLen; const AOptions: TKBDynamicOptions); forward;

procedure DynamicRead_Record(AStream: TStream; ADynamic: Pointer;
  AFieldTable: PFieldTable; const AOptions: TKBDynamicOptions);
var
  lCompare: KBPointerMath;
  lOffset: KBPointerMath;
  lIdx: KBPointerMath;
  lTypeInfo: PTypeInfo;
begin
  if AFieldTable^.Count = 0 then
  begin
    TStream_ReadBuffer(AStream, PByte(ADynamic)^, AFieldTable.Size);
    Exit;
  end;

  lCompare := 0;
  lIdx := 0;

  while (lCompare < AFieldTable^.Size) and (lIdx < AFieldTable^.Count) do
  begin
    lOffset := AFieldTable^.Fields[lIdx].Offset;

    if lCompare < lOffset then
    begin
      TStream_ReadBuffer(AStream, PByte(KBPointerMath(ADynamic) + lCompare)^, lOffset - lCompare);
      Inc(lCompare, lOffset - lCompare);
    end;

    lTypeInfo := AFieldTable^.Fields[lIdx].TypeInfo^;

    DynamicRead_Array(
      AStream,
      Pointer(KBPointerMath(ADynamic) + lOffset),
      lTypeInfo,
      1,
      AOptions
    );

    case lTypeInfo^.Kind of
    tkArray, tkRecord:
      Inc(lCompare, PFieldTable(KBPointerMath(lTypeInfo) + PByte(@lTypeInfo^.Name)^)^.Size);
    else
      Inc(lCompare, SizeOf(Pointer));
    end;

    Inc(lIdx);
  end;

  if lCompare < AFieldTable^.Size then
    TStream_ReadBuffer(AStream, PByte(KBPointerMath(ADynamic) + lCompare)^, AFieldTable^.Size - lCompare);
end;

procedure DynamicRead_DynArray(AStream: TStream; ADynamic: Pointer;
  ATypeInfo: PTypeInfo; const AOptions: TKBDynamicOptions);
var
  lDyn: PDynArrayTypeInfo;
  lLen: KBArrayLen;
begin
  if kdoLimitToWordSize in AOptions then
  begin
    lLen := 0;
    TStream_ReadBuffer(AStream, lLen, SizeOf(Word));
  end else
    if kdoCPUArchCompatibility in AOptions then
    begin
      lLen := 0;
      TStream_ReadBuffer(AStream, lLen, SizeOf(KBArrayLen86));
    end else
      TStream_ReadBuffer(AStream, lLen, SizeOf(KBArrayLen));

  DynArraySetLength(PPointer(ADynamic)^, ATypeInfo, 1, @lLen);

  if lLen = 0 then
    Exit;

  lDyn := PDynArrayTypeInfo(KBPointerMath(ATypeInfo) + PByte(@ATypeInfo^.Name)^);

  if lDyn^.elType = nil then
    TStream_ReadBuffer(AStream, PByte(ADynamic^)^, lLen * lDyn^.elSize)
  else
    DynamicRead_Array(
      AStream,
      PPointer(ADynamic)^,
      PTypeInfo(lDyn^.elType^),
      lLen,
      AOptions
    );
end;

procedure DynamicRead_Array(AStream: TStream; ADynamic: Pointer;
  ATypeInfo: PTypeInfo; ALength: KBArrayLen; const AOptions: TKBDynamicOptions);
var
  lFieldTable: PFieldTable;
  lStrLen: KBStrLen;
  lUTF8: Pointer;
begin
  if ALength = 0 then
    Exit;

  case ATypeInfo^.Kind of
  {$IF Declared(AnsiString)}
  tkLString:
    while ALength > 0 do
    begin
      if kdoLimitToWordSize in AOptions then
      begin
        lStrLen := 0;
        TStream_ReadBuffer(AStream, lStrLen, SizeOf(Word));
      end else
        TStream_ReadBuffer(AStream, lStrLen, SizeOf(KBStrLen));

      SetLength(PAnsiString(ADynamic)^, lStrLen);

      if lStrLen > 0 then
      begin
        TStream_ReadBuffer(AStream, PByte(ADynamic^)^, lStrLen * SizeOf(AnsiChar));
        if kdoAnsiStringCodePage in AOptions then
          {$IF Declared(UnicodeString)}
          TStream_ReadBuffer(AStream, PWord(PKBPointerMath(ADynamic)^ - 12)^, SizeOf(Word));   // StrRec.codePage
          {$ELSE}
          AStream.Seek(SizeOf(Word), soFromCurrent); // TODO: try to convert from one codepage to another
          {$IFEND}
      end;

      Inc(PPointer(ADynamic));
      Dec(ALength);
    end;
  {$IFEND}

  {$IF Declared(WideString)}
  tkWString:
    while ALength > 0 do
    begin
      if kdoLimitToWordSize in AOptions then
      begin
        lStrLen := 0;
        TStream_ReadBuffer(AStream, lStrLen, SizeOf(Word));
      end else
        TStream_ReadBuffer(AStream, lStrLen, SizeOf(KBStrLen));

      if lStrLen = 0 then
        SetLength(PWideString(ADynamic)^, 0)
      else
        if kdoUTF16ToUTF8 in AOptions then
        begin
          GetMem(lUTF8, lStrLen);
          if AStream.Read(lUTF8^, lStrLen) <> lStrLen then
          begin
            FreeMem(lUTF8);
            raise EReadError.CreateRes(@SReadError);
          end;

          SetLength(PWideString(ADynamic)^, Utf8ToUnicode(nil, MaxInt, lUTF8, lStrLen));
          if Length(PWideString(ADynamic)^) = 0 then
          begin
            FreeMem(lUTF8);
            raise EKBDynamic.Create('Utf8ToUnicode failed!');
          end;

          Utf8ToUnicode(@PWideString(ADynamic)^[1], Length(PWideString(ADynamic)^) + 1, lUTF8, lStrLen);
          FreeMem(lUTF8);
        end else
        begin
          SetLength(PWideString(ADynamic)^, lStrLen);

          TStream_ReadBuffer(AStream, PByte(ADynamic^)^, lStrLen * SizeOf(WideChar));
        end;

      Inc(PPointer(ADynamic));
      Dec(ALength);
    end;
  {$IFEND}

  {$IF Declared(UnicodeString)}
  tkUString:
    while ALength > 0 do
    begin
      if kdoLimitToWordSize in AOptions then
      begin
        lStrLen := 0;
        TStream_ReadBuffer(AStream, lStrLen, SizeOf(Word));
      end else
        TStream_ReadBuffer(AStream, lStrLen, SizeOf(KBStrLen));

      if lStrLen = 0 then
        SetLength(PUnicodeString(ADynamic)^, 0)
      else
        if kdoUTF16ToUTF8 in AOptions then
        begin
          GetMem(lUTF8, lStrLen);
          if AStream.Read(lUTF8^, lStrLen) <> lStrLen then
          begin
            FreeMem(lUTF8);
            raise EReadError.CreateRes(@SReadError);
          end;

          SetLength(PUnicodeString(ADynamic)^, Utf8ToUnicode(nil, MaxInt, lUTF8, lStrLen));
          if Length(PUnicodeString(ADynamic)^) = 0 then
          begin
            FreeMem(lUTF8);
            raise EKBDynamic.Create('Utf8ToUnicode failed!');
          end;

          Utf8ToUnicode(@PUnicodeString(ADynamic)^[1], Length(PUnicodeString(ADynamic)^) + 1, lUTF8, lStrLen);
          FreeMem(lUTF8);
        end else
        begin
          SetLength(PUnicodeString(ADynamic)^, lStrLen);

          TStream_ReadBuffer(AStream, PByte(ADynamic^)^, lStrLen * SizeOf(WideChar));
        end;

      Inc(PPointer(ADynamic));
      Dec(ALength);
    end;
  {$IFEND}

  tkArray:
    begin
      lFieldTable := PFieldTable(KBPointerMath(ATypeInfo) + PByte(@PTypeInfo(ATypeInfo).Name)^);
      while ALength > 0 do
      begin
        DynamicRead_Array(
          AStream,
          ADynamic,
          lFieldTable.Fields[0].TypeInfo^,
          lFieldTable.Count,
          AOptions);

        Inc(KBPointerMath(ADynamic), lFieldTable.Size);
        Dec(ALength);
      end;
    end;

  tkRecord:
    begin
      lFieldTable := PFieldTable(KBPointerMath(ATypeInfo) + PByte(@PTypeInfo(ATypeInfo).Name)^);
      while ALength > 0 do
      begin
        DynamicRead_Record(AStream, ADynamic, lFieldTable, AOptions);
        Inc(KBPointerMath(ADynamic), lFieldTable.Size);
        Dec(ALength);
      end;
    end;

  tkDynArray:
    while ALength > 0 do
    begin
      DynamicRead_DynArray(AStream, ADynamic, ATypeInfo, AOptions);
      Inc(KBPointerMath(ADynamic), SizeOf(Pointer));
      Dec(ALength);
    end;
  else
    raise EKBDynamicInvalidType.Create(ATypeInfo^.Kind);
  end;
end;

{ TKBDynamic }

class function TKBDynamic.Compare(const ADynamicType1,
  ADynamicType2; ATypeInfo: PTypeInfo): Boolean;
begin
  Result := DynamicCompare_Array(@ADynamicType1, @ADynamicType2, ATypeInfo, 1);
end;

class function TKBDynamic.GetSize(const ADynamicType;
  ATypeInfo: PTypeInfo; const AOptions: TKBDynamicOptions): KBSize;
begin
  Result := SizeOf(TKBDynamicHeader) + GetSizeNH(ADynamicType, ATypeInfo, AOptions);
end;

class function TKBDynamic.GetSizeNH(const ADynamicType;
  ATypeInfo: PTypeInfo; const AOptions: TKBDynamicOptions): KBSize;
begin
  Result := DynamicGetSize_Array(@ADynamicType, ATypeInfo, 1, AOptions);
end;

class procedure TKBDynamic.WriteTo(AStream: TStream; const ADynamicType;
  ATypeInfo: PTypeInfo; AVersion: Word; const AOptions: TKBDynamicOptions; APreAllocSize: Boolean);
var
  lHeader: TKBDynamicHeader;
  lNewSize: Int64;
  lOldPos: Int64;
  lOptions: Byte;
begin
  if APreAllocSize then
  begin
    lNewSize := AStream.Position + TKBDynamic.GetSize(ADynamicType, ATypeInfo, AOptions);
    if lNewSize > AStream.Size then
    begin
      lOldPos := AStream.Position;
      AStream.Size := lNewSize;
      AStream.Position := lOldPos;
    end;
  end;

  lOptions := 0;

  {$IF Declared(UnicodeString)}
  lOptions := lOptions or cKBDYNAMIC_STREAM_CFG_UNICODE;
  {$IFEND}

  if kdoUTF16ToUTF8 in AOptions then
    lOptions := lOptions or cKBDYNAMIC_STREAM_CFG_UTF8;

  if kdoLimitToWordSize in AOptions then
    lOptions := lOptions or cKBDYNAMIC_STREAM_CFG_WORDSIZE;

  if kdoAnsiStringCodePage in AOptions then
    lOptions := lOptions or cKBDYNAMIC_STREAM_CFG_CODEPAGE;

  if kdoCPUArchCompatibility in AOptions then
    lOptions := lOptions or cKBDYNAMIC_STREAM_CFG_CPUARCH;

  {$IFDEF CPUX64}
  if kdoCPUArchCompatibility in AOptions then
    lHeader.Stream.Version := cKBDYNAMIC_STREAM_VERSION_v1
  else
    lHeader.Stream.Version := cKBDYNAMIC_STREAM_VERSION_v2;
  {$ELSE}
  lHeader.Stream.Version := cKBDYNAMIC_STREAM_VERSION_v1;
  {$ENDIF}

  lHeader.Stream.Options := lOptions;
  lHeader.TypeVersion := AVersion;

  TStream_WriteBuffer(AStream, lHeader, SizeOf(lHeader));

  WriteToNH(AStream, ADynamicType, ATypeInfo, AOptions);
end;

class procedure TKBDynamic.WriteToNH(AStream: TStream;
  const ADynamicType; ATypeInfo: PTypeInfo; const AOptions: TKBDynamicOptions);
begin
  DynamicWrite_Array(AStream, @ADynamicType, ATypeInfo, 1, AOptions);
end;

class function TKBDynamic.ReadFrom(AStream: TStream; const ADynamicType;
  ATypeInfo: PTypeInfo; AVersion: Word; AForceCPUArchCompatibilityOnStreamV1: Boolean): Boolean;
var
  lHeader: TKBDynamicHeader;
  lOptions: TKBDynamicOptions;
begin
  lOptions := [];

  TStream_ReadBuffer(AStream, lHeader, SizeOf(lHeader));
  Result := lHeader.TypeVersion = AVersion;

  if Result then
  begin
    if cKBDYNAMIC_STREAM_CFG_UTF8 and lHeader.Stream.Options = cKBDYNAMIC_STREAM_CFG_UTF8 then
      Include(lOptions, kdoUTF16ToUTF8);

    if cKBDYNAMIC_STREAM_CFG_WORDSIZE and lHeader.Stream.Options = cKBDYNAMIC_STREAM_CFG_WORDSIZE then
      Include(lOptions, kdoLimitToWordSize);

    if cKBDYNAMIC_STREAM_CFG_CODEPAGE and lHeader.Stream.Options = cKBDYNAMIC_STREAM_CFG_CODEPAGE then
      Include(lOptions, kdoAnsiStringCodePage);

    if (cKBDYNAMIC_STREAM_CFG_CPUARCH and lHeader.Stream.Options = cKBDYNAMIC_STREAM_CFG_CPUARCH) or
      (AForceCPUArchCompatibilityOnStreamV1 and (lHeader.Stream.Version = cKBDYNAMIC_STREAM_VERSION_v1))
    then
      Include(lOptions, kdoCPUArchCompatibility);

    {$IFDEF CPUX64}
    if kdoCPUArchCompatibility in lOptions then
      Result := lHeader.Stream.Version = cKBDYNAMIC_STREAM_VERSION_v1
    else
      Result := lHeader.Stream.Version = cKBDYNAMIC_STREAM_VERSION_v2;
    {$ELSE}
    Result := lHeader.Stream.Version = cKBDYNAMIC_STREAM_VERSION_v1;
    {$ENDIF}
  end;

  if Result then
    ReadFromNH(AStream, ADynamicType, ATypeInfo, lOptions)
  else
    AStream.Seek(-SizeOf(lHeader), soCurrent);
end;

class procedure TKBDynamic.ReadFromNH(AStream: TStream;
  const ADynamicType; ATypeInfo: PTypeInfo;
  const AOptions: TKBDynamicOptions);
begin
  DynamicRead_Array(AStream, @ADynamicType, ATypeInfo, 1, AOptions);
end;

{ EKBDynamicInvalidType }

constructor EKBDynamicInvalidType.Create(ATypeKind: TTypeKind);
begin
  FTypeKind := ATypeKind;

  inherited CreateFmt('Unsupported field type %s', [
    GetEnumName(TypeInfo(TTypeKind), Ord(ATypeKind))
  ]);
end;

{ EKBDynamicLimit }

constructor EKBDynamicLimit.Create(ALen, AMaxLen: KBArrayLen);
begin
  inherited CreateFmt('Invalid dynamic array size %d (max %d)', [ALen, AMaxLen]);
end;

{ EKBDynamicWordLimit }

constructor EKBDynamicWordLimit.Create(ALen: KBArrayLen);
begin
  inherited Create(ALen, MAXWORD);
end;

end.
