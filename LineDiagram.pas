{ Alexander Shyshko, 2018, alitrun@gmail.com }

unit LineDiagram;

interface

uses
  FMX.Objects, FMX.Graphics, System.Types, System.UITypes, Classes, Math, System.Generics.Collections,
  System.Generics.Defaults, SysUtils, FMX.Graphics.Native, FMX.Controls, FMX.PLatform;

type
  TOnStartEndMoveTrack = procedure (aSender: TObject; aMoving: boolean) of object;
  TOnChangeTrack = procedure (aIndex: integer) of object;
  // aIndex - index in array, same as hours 0 - 23

  TLineDiagram = class(TPaintBox)
  strict private
    fMinX, fMaxX: integer;  // values of data (e.g. hours etc that present X coordinates)
    fMinY, fMaxY: integer; // values of data (e.g. temperature etc that present Y coordinates)
    fXStep, fYStep: Single; // ratio beetween pixels and data values(temperature, hours et)
    const
      X_LEFT_MARGIN = 5;  // left margin of the graph on fBitmap
      X_RIGHT_MARGION = 5;
      Y_BOTTOM_MARGIN = 5;
      Y_TOP_MARGIN = 5;
      LINE_COLOR = $ff25AAE1; // blue
      LABEL_TIME_TOP_OFFSET = 5; // increase to set time label lower
      LINE_THICKNESS = 3;
  strict private
    fTrack: TSelectionPoint;
    fPathArrayIndex: integer; // prevent updating GUI with same data
    fTrackLastXY: TPoint;
    fPathsBitmap: TBitmap; // temporary bitmap to scan and find path points for TrackPoint
    fShowTrack: boolean;
    fTrackPath: array of TPoint; // track point moves on these point coordinates
    fOnStartEndMoveTrack: TOnStartEndMoveTrack;
    fOnChangeTrack: TOnChangeTrack;
    procedure OnTrackPointChanged(Sender: TObject; var X, Y: Single);
    procedure ScanBitmapForPoints;
    procedure DrawToPathBitmap(Canvas: TCanvas; aPath: TPathData);
    procedure TrackMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure TrackMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    function FindNearestXYInPath(aSearchXY: TPoint): integer;
  strict private
    fBitmap: TBitmap;
    flblTime: TText;
    fInitiated: boolean;
    procedure ResetOnNewGraphDraw;
    function ConvertXYToReal(aXY: TPoint): TPointF; inline;
    procedure InitStep;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure DrawGraph(Canvas: TCanvas; aRect: TRectF);
  public
    XYArray: array of TPoint;
    LineThickness: integer;
    constructor Create(AOwner: TComponent; aShowTrack: boolean); reintroduce; overload;
    destructor Destroy; override;
    procedure AddRangeXY(aMinX, aMinY, aMaxX, aMaxY: integer);
    procedure Clear;
    procedure InitGraph;
    procedure SetTrackPosition(aHour: integer);
    property OnStartEndMoveTrack: TOnStartEndMoveTrack read fOnStartEndMoveTrack write fOnStartEndMoveTrack;
    property OnChangeTrack: TOnChangeTrack read fOnChangeTrack write fOnChangeTrack;
  end;


  {$DEFINE UseNativeDraw}
implementation

{ TLineDiagram }

constructor TLineDiagram.Create(AOwner: TComponent; aShowTrack: boolean);
begin
  inherited Create(AOwner);
  fBitmap := TBitmap.Create();
  if aShowTrack then
  begin
    fTrack := TSelectionPoint.Create(nil);
    fTrack.Parent := Self;
    fTrack.GripSize := 60;
    fTrack.StyleLookup := '1selectionpoint';
    fTrack.OnTrack := OnTrackPointChanged;
    fTrack.OnMouseDown := TrackMouseDown;
    fTrack.OnMouseUp := TrackMouseUp;
    fTrack.Visible := false;

    // create label
    flblTime := TText.Create(nil);
    flblTime.Parent := Self;
    flblTime.TextSettings.BeginUpdate;
    flblTime.TextSettings.Font.Size := 13;
    flblTime.TextSettings.WordWrap := false;
    flblTime.AutoSize := true;
    flblTime.Text := 'text';
    flblTime.HitTest := false;
    flblTime.Visible := false;
    flblTime.TextSettings.EndUpdate;
  end;
  fShowTrack := aShowTrack;
  LineThickness := LINE_THICKNESS;
end;

destructor TLineDiagram.Destroy;
begin
  fBitmap.Free;
  flblTime.Free;
  fTrack.Free;
  inherited;
end;

procedure TLineDiagram.DrawGraph(Canvas: TCanvas; aRect: TRectF);

  procedure PreprarePath(var aPath: TPathData);
  var
    i: integer;
    pi, pi1, EndP: TPointF;  // point i, point i + 1
  begin
    EndP := ConvertXYToReal(XYArray[0]);
    aPath.MoveTo(EndP);

    for i := 1 to Length(XYArray) - 2 do
    begin
      pi := ConvertXYToReal(XYArray[i]);
      pi1 := ConvertXYToReal(XYArray[i + 1]);

      EndP.X := (pi.x + pi1.x) / 2;
      EndP.Y := (pi.y + pi1.y) / 2;
      aPath.QuadCurveTo(pi, EndP);

      // curve through the last two points
      if i = Length(XYArray) - 3 then
        aPath.QuadCurveTo(ConvertXYToReal(XYArray[i+1]), ConvertXYToReal(XYArray[i+2]));
    end;
  end;

var
  lPath: TPathData;
begin
  if Length(XYArray) = 0 then exit;

  lPath := TPathData.Create;
  Canvas.BeginScene();
  try
    with Canvas.Stroke do
    begin
      Cap := TStrokeCap.Round;
      Kind := TBrushKind.Solid;
      Color := LINE_COLOR;// blue
      Thickness := LineThickness;
    end;

    PreprarePath(lPath);

    {$IFDEF UseNativeDraw } Canvas.NativeDraw(aRect,
    procedure
    begin  {$ENDIF}
      Canvas.DrawPath(lPath, 1);
    {$IFDEF UseNativeDraw}
    end ); {$ENDIF}

    // now draw path in temp bitmap to scan it later and find path points
    if fShowTrack then
    begin
      fTrack.Visible := true;
      flblTime.Visible := true;
      Assert(fPathsBitmap = nil);
      fPathsBitmap := TBitmap.Create(Trunc(Width), Trunc(Height)); // free it later, after scan
      DrawToPathBitmap(fPathsBitmap.Canvas, lPath);
    end;
  finally
    Canvas.EndScene();
    lPath.Free;
  end;
end;

procedure TLineDiagram.DrawToPathBitmap(Canvas: TCanvas; aPath: TPathData);
begin
  Canvas.BeginScene();
  try
    with Canvas.Stroke do
    begin
      Color := TAlphaColorRec.Black;
      Kind := TBrushKind.Solid;
      Thickness := 1;
    end;

   {$IFDEF UseNativeDraw } Canvas.NativeDraw(fPathsBitmap.BoundsF,
    procedure
    begin  {$ENDIF}

      Canvas.DrawPath(aPath, 1);

   {$IFDEF UseNativeDraw}
    end ); {$ENDIF}

  finally
    Canvas.EndScene;
  end;

end;

procedure TLineDiagram.Paint;

  procedure DrawVerticalLine;
  const
    BOTTOM_MARGIN = 8;
  begin
    {$IFDEF UseNativeDraw } Canvas.NativeDraw(LocalRect,
    procedure
    begin  {$ENDIF}
      Canvas.Stroke.Color := LINE_COLOR;
      Canvas.Stroke.Thickness := 1;
      Canvas.Stroke.Kind := TBrushKind.Solid;
      Canvas.DrawLine(PointF(fTrackLastXY.X, 0), PointF(fTrackLastXY.X, Height - BOTTOM_MARGIN), 1);
    {$IFDEF UseNativeDraw}
    end ); {$ENDIF}
  end;

begin
  inherited;
  if not fInitiated then
    InitGraph;

  Canvas.DrawBitmap(fBitmap, fBitmap.BoundsF, LocalRect, 1);

  if fShowTrack then
    DrawVerticalLine;
end;

{If you do not use Track Point - do not need to call this func at all.
Init means to draw graph on bitmap and scan it to find Path points for track point.
 Before, init func was in Paint method, but we need to set track point position on already drawed graph
 before Paint}
procedure TLineDiagram.InitGraph;
begin
  if Length(XYArray) = 0 then exit;

  DrawGraph(fBitmap.Canvas, fBitmap.BoundsF);

  if fShowTrack then
  begin
    ResetOnNewGraphDraw;
    ScanBitmapForPoints; // this is a heavy operation, move it to thread?
  end;
  fInitiated := true;
end;

//  init routings after new graph has been drew, like set position of trackpoint etc.
procedure TLineDiagram.ResetOnNewGraphDraw;
begin
  fTrack.Position.Point := ConvertXYToReal(XYArray[0]);
  fTrackLastXY := Point( Trunc(fTrack.Position.Point.X), Trunc(fTrack.Position.Point.Y));
  flblTime.Position.Y := Height + LABEL_TIME_TOP_OFFSET;
  flblTime.Text := '00:00';
end;

// convert virtual coordiantes like temperature and hours to real on canvas
function TLineDiagram.ConvertXYToReal(aXY: TPoint): TPointF;
begin
  Result.X := (aXY.X * fXStep - fMinX * fXStep) + X_LEFT_MARGIN;
  Result.Y := (aXY.Y * fYStep - fMinY * fYStep ) ;

  // now we have coord. from left top corner, invert it to traditional bottom left coord.
  Result.Y := Height - Y_BOTTOM_MARGIN - Result.Y;
end;

procedure TLineDiagram.AddRangeXY(aMinX, aMinY, aMaxX, aMaxY: integer);
begin
  fMinX := aMinX;
  fMaxX := aMaxX;
  fMinY := aMinY;
  fMaxY := aMaxY;
  InitStep;
end;

procedure TLineDiagram.InitStep;
var
  lVal: integer;
begin
  if fMaxX > 0 then
  begin
    lVal := (fMaxY - fMinY);
    if lVal <= 0 then
      fYStep := 0
    else
      fYStep := (Height - Y_BOTTOM_MARGIN - Y_TOP_MARGIN) / lVal;

    fXStep := (Width - X_LEFT_MARGIN - X_RIGHT_MARGION) / (fMaxX - fMinX);
    // subtruct from width to reduce width of graph from right side
  end;
end;

procedure TLineDiagram.Resize;

  procedure ResizeGraphBitmap;
  var
    lScale: Single;
  begin
    if Scene <> nil then
      lScale := Scene.GetSceneScale
    else
      lScale := 1;

    fBitmap.BitmapScale := lScale;
    // scale it with current scale, so it will be larger than PaintBox, - in this case it
    //  draws bitmap with antialiasing
    fBitmap.SetSize(Ceil(Width * lScale), Ceil(Height * lScale) );
  end;

begin
  //Assert(fMaxX <> 0, 'Set fMaxX, fMinY to draw graph');
  inherited;

  // reset array with coordinates to move track point
  fTrackPath := nil;
  fInitiated := false;

  ResizeGraphBitmap;
  InitStep;
end;

procedure TLineDiagram.OnTrackPointChanged(Sender: TObject; var X, Y: Single);

  procedure SetTimeLabelPos;
  const
    BOTTOM_OFFSET = 5;
  var
    lIndex: integer;
  begin
    flblTime.Position.X := X - flblTime.Width * 0.5;
    flblTime.Position.Y := Height + LABEL_TIME_TOP_OFFSET; // - flblTime.Height;
    lIndex := Trunc(X / fXStep);

    if lIndex >= Length(XYArray) then
      lIndex := High(XYArray);

    flblTime.Text := IntToStr(XYArray[lIndex].X) + ':00';
  end;

var
  lSearchValue: TPoint;
  lFoundIndex: integer; // in fTrackPath array
  lNewIndex: integer;
begin
  // workaround: each time track returns such positions
  if (X + Y = 0) or (X > fTrackPath[High(fTrackPath)].X) then
  begin
    X := fTrackLastXY.X;
    Y := fTrackLastXY.Y;
    exit;
  end;

  lSearchValue := Point( Trunc(fTrack.Position.X), Trunc(fTrack.Position.Y) );

  // detect moving direction - right or left
  lFoundIndex := FindNearestXYInPath(lSearchValue);
  // search closest XY for current track XY in path array
  if lFoundIndex = -1 then exit;

  {Now X was found in path array, that is ~ current track XY.
   Increase FoundIndex to find next X that <> current X. Should do it in a loop,
   because X can be repeated - Like [150].X = 125, [151].X = 125 etc - this depends on graph line path}

  // detect moving direction
  // right
  if X >= fTrackLastXY.X then
  begin
    while (lFoundIndex <> High(fTrackPath)) and (fTrackPath[lFoundIndex].X <= X) do
      inc(lFoundIndex);
  end     //
  else
  // left
  begin
    while (lFoundIndex <> 0) and (fTrackPath[lFoundIndex].X >= X) do
     dec(lFoundIndex);
  end;

  X := fTrackPath[lFoundIndex].X;
  Y := fTrackPath[lFoundIndex].Y;

  fTrackLastXY.X := Trunc(X);
  fTrackLastXY.Y := Trunc(Y);

  SetTimeLabelPos;

  // fPathArrayIndex to prevent updating GUI with same data
  lNewIndex := Trunc(X / fXStep);
  if fPathArrayIndex <> lNewIndex then
  begin
    fPathArrayIndex := lNewIndex;
    Assert(lNewIndex <= 23);
    if Assigned(fOnChangeTrack) then
      fOnChangeTrack(lNewIndex);
  end;
end;

procedure TLineDiagram.SetTrackPosition(aHour: integer);
var
  lPos: TPoint;
  lIndex: integer;
  X, Y: single;
begin

  lPos.X := Trunc(aHour * fXStep);
  lPos.Y := 0;

  lIndex := FindNearestXYInPath(lPos);
  if lIndex = -1 then exit;

  X := fTrackPath[lIndex].X;
  Y := fTrackPath[lIndex].Y;

  fTrackLastXY.X := Trunc(X);
  fTrackLastXY.Y := Trunc(Y);
  fTrack.Position.Point := fTrackLastXY;

  OnTrackPointChanged(nil, X, Y);
end;

// search nearest XY in path array, return index in fTrackPath array with coordinates
// -1 if does not found nearest value
function TLineDiagram.FindNearestXYInPath(aSearchXY: TPoint): integer;
var
  lComparer: IComparer<TPoint>;
begin
  lComparer := TDelegatedComparer<TPoint>.Create(
  function(const aLeft, aRight: TPoint): Integer
  begin
    if aLeft.X > aRight.X then
      Result := 1
    else
      if aLeft.X < aRight.X then
        Result := -1
      else
        Result := 0;
  end);

  // search closest XY for current track XY in path array
  if not TArray.BinarySearch<TPoint>(fTrackPath, aSearchXY, Result, lComparer) then
    Result := 0; // 00:00 hour.
end;

{ Scan graph bitmap and build array of points of line.}
procedure TLineDiagram.ScanBitmapForPoints;
var
  lData: TBitmapData;
  X, Y, lIndex: Integer;
begin
  Assert(fPathsBitmap <> nil);
  if not fPathsBitmap.Map(TMapAccess.Read, lData) then
    raise Exception.Create('Cannot read the map of graph bitmap');

  SetLength(fTrackPath, Trunc(Width));
  lIndex := 0;

  // scan from bottom left - to right top
  for X := 0 to lData.Width - 1 do
  begin
    for Y := lData.Height-1 downto 0 do
    begin
      {search for color pixel. 0 means no color. We can't search for concrete color (e.g. black),
       because FMX draws with AA - so if user draws only with black - closer pixels became lighter}
      if lData.GetPixel(X, Y) <> 0 then
      begin
        if lIndex > High(fTrackPath) then
          SetLength(fTrackPath, High(fTrackPath) + Trunc(Width));

        fTrackPath[lIndex].X := X;
        fTrackPath[lIndex].Y := Y;
        Inc(lIndex);
      end;
    end;
  end;
  // cut data at the end with nulls
  SetLength(fTrackPath, lIndex);

  FreeAndNil(fPathsBitmap);
end;


procedure TLineDiagram.TrackMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Single);
begin
  if Assigned(fOnStartEndMoveTrack) then
    fOnStartEndMoveTrack(Self, true);
end;

procedure TLineDiagram.TrackMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if Assigned(fOnStartEndMoveTrack) then
    fOnStartEndMoveTrack(Self, false);
end;

procedure TLineDiagram.Clear;
begin
  fPathArrayIndex := -1;
  fBitmap.Clear(TAlphaColorRec.White);
  XYArray := nil;
  fInitiated := false;
  fTrack.Visible := false;
  flblTime.Visible := false;
end;


end.
