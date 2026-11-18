'==============================================================================
' WeeklyReport.bas
' Refreshes the Power Query data, builds a one-page weekly returns report by
' category (latest week vs prior week), and exports it as a PDF.
'
' Expects:
'   An Excel table (ListObject) named "weekly_kpis" on any sheet, loaded by
'   Power Query from weekly_kpis.csv, with at least these columns:
'     week_start, category, items_delivered, items_returned, returned_revenue
'   Background refresh turned OFF on the query, so RefreshAll finishes first.
'
' Creates or clears sheet "Report". Uses no Windows-only libraries, so it also
' runs in Excel for Mac.
'
' Import: VBA editor (Alt+F11 / Tools > Macro > Visual Basic Editor)
'         > File > Import File... > WeeklyReport.bas, then save as .xlsm
'==============================================================================
Option Explicit

Private Const DATA_TABLE As String = "weekly_kpis"
Private Const REPORT_SHEET As String = "Report"
Private Const MAX_CATEGORIES As Long = 200
Private Const MIN_ITEMS_FLAG As Long = 30   ' below this, a week's rate is too noisy to flag

' Columns of the aggregation array
Private Const A_DEL_NOW As Long = 1
Private Const A_RET_NOW As Long = 2
Private Const A_DEL_PRIOR As Long = 3
Private Const A_RET_PRIOR As Long = 4
Private Const A_RETREV_NOW As Long = 5

Public Sub BuildWeeklyReport()
    Dim lo As ListObject
    Dim data As Variant
    Dim cWeek As Long, cCat As Long, cDel As Long, cRet As Long, cRetRev As Long
    Dim latest As Date, prior As Date, wk As Date
    Dim cats() As String, agg() As Double, n As Long
    Dim r As Long, i As Long
    Dim ws As Worksheet
    Dim pdfPath As String, pdfMsg As String

    On Error GoTo Fail
    Application.ScreenUpdating = False
    Application.StatusBar = "Refreshing data..."

    ' 1. Refresh Power Query (the "data link")
    ThisWorkbook.RefreshAll
    Application.CalculateUntilAsyncQueriesDone

    ' 2. Read the table into an array (much faster than reading cell by cell)
    Set lo = FindTable(DATA_TABLE)
    If lo.DataBodyRange Is Nothing Then
        Err.Raise vbObjectError + 1, , "Table '" & DATA_TABLE & "' is empty."
    End If

    cWeek = ColIndex(lo, "week_start")
    cCat = ColIndex(lo, "category")
    cDel = ColIndex(lo, "items_delivered")
    cRet = ColIndex(lo, "items_returned")
    cRetRev = ColIndex(lo, "returned_revenue")

    data = lo.DataBodyRange.Value

    ' 3. Find the latest week in the data
    For r = 1 To UBound(data, 1)
        If IsDate(data(r, cWeek)) Then
            wk = CDate(data(r, cWeek))
            If wk > latest Then latest = wk
        End If
    Next r
    If latest = 0 Then Err.Raise vbObjectError + 2, , "No valid dates in week_start."
    prior = latest - 7

    ' 4. Aggregate latest and prior week by category
    ReDim cats(1 To MAX_CATEGORIES)
    ReDim agg(1 To MAX_CATEGORIES, 1 To 5)
    n = 0

    Application.StatusBar = "Aggregating..."
    For r = 1 To UBound(data, 1)
        If IsDate(data(r, cWeek)) Then
            wk = CDate(data(r, cWeek))
            If wk = latest Or wk = prior Then
                i = FindOrAdd(cats, n, CStr(data(r, cCat)))
                If wk = latest Then
                    agg(i, A_DEL_NOW) = agg(i, A_DEL_NOW) + Num(data(r, cDel))
                    agg(i, A_RET_NOW) = agg(i, A_RET_NOW) + Num(data(r, cRet))
                    agg(i, A_RETREV_NOW) = agg(i, A_RETREV_NOW) + Num(data(r, cRetRev))
                Else
                    agg(i, A_DEL_PRIOR) = agg(i, A_DEL_PRIOR) + Num(data(r, cDel))
                    agg(i, A_RET_PRIOR) = agg(i, A_RET_PRIOR) + Num(data(r, cRet))
                End If
            End If
        End If
    Next r

    ' 5. Write the report
    Application.StatusBar = "Writing report..."
    Set ws = GetOrCreateSheet(REPORT_SHEET)
    WriteReport ws, cats, agg, n, latest, prior

    ' 6. Export PDF next to the workbook (a failure here does not lose the report)
    pdfPath = ThisWorkbook.Path & Application.PathSeparator & _
              "weekly_returns_report_" & Format(latest, "yyyy-mm-dd") & ".pdf"
    pdfMsg = ExportPdf(ws, pdfPath)

    ws.Activate
    Application.StatusBar = False
    Application.ScreenUpdating = True
    MsgBox "Weekly report built for week of " & Format(latest, "d mmm yyyy") & _
           "." & vbCrLf & vbCrLf & pdfMsg, vbInformation
    Exit Sub

Fail:
    Application.StatusBar = False
    Application.ScreenUpdating = True
    MsgBox "BuildWeeklyReport failed: " & Err.Description, vbExclamation
End Sub

'------------------------------------------------------------------------------
' Writes the report table, totals, formatting and print setup.
'------------------------------------------------------------------------------
Private Sub WriteReport(ws As Worksheet, cats() As String, agg() As Double, _
                        n As Long, latest As Date, prior As Date)
    Const FIRST_ROW As Long = 5      ' header row of the table
    Dim out() As Variant
    Dim i As Long, lastRow As Long, totalRow As Long
    Dim body As Range, rateCol As Range, changeCol As Range

    ws.Cells.Clear
    ws.Cells.FormatConditions.Delete

    ' Title block
    ws.Range("A1").Value = "Weekly Returns Report"
    ws.Range("A1").Font.Size = 16
    ws.Range("A1").Font.Bold = True
    ws.Range("A2").Value = "Week of " & Format(latest, "d mmm yyyy") & _
                           "  (compared with week of " & Format(prior, "d mmm yyyy") & ")"
    ws.Range("A3").Value = "Source: thelook_ecommerce via weekly_kpis.csv. Refreshed " & _
                           Format(Now, "d mmm yyyy hh:nn") & "."
    ws.Range("A3").Font.Italic = True

    ' Headers
    ws.Cells(FIRST_ROW, 1).Resize(1, 7).Value = Array( _
        "Category", "Items delivered", "Items returned", "Return rate", _
        "Prior week rate", "Change (pp)", "Returned revenue")

    If n = 0 Then
        ws.Cells(FIRST_ROW + 1, 1).Value = "No data for the latest week."
        Exit Sub
    End If

    ' Body: values for counts, formulas for rates (so the logic is visible in the sheet)
    ReDim out(1 To n, 1 To 7)
    For i = 1 To n
        out(i, 1) = cats(i)
        out(i, 2) = agg(i, A_DEL_NOW)
        out(i, 3) = agg(i, A_RET_NOW)
        out(i, 4) = Empty
        If agg(i, A_DEL_PRIOR) > 0 Then
            out(i, 5) = agg(i, A_RET_PRIOR) / agg(i, A_DEL_PRIOR)
        Else
            out(i, 5) = Empty
        End If
        out(i, 6) = Empty
        out(i, 7) = agg(i, A_RETREV_NOW)
    Next i

    lastRow = FIRST_ROW + n
    Set body = ws.Range(ws.Cells(FIRST_ROW + 1, 1), ws.Cells(lastRow, 7))
    body.Value = out

    ws.Range(ws.Cells(FIRST_ROW + 1, 4), ws.Cells(lastRow, 4)).Formula = _
        "=IFERROR(C" & FIRST_ROW + 1 & "/B" & FIRST_ROW + 1 & ","""")"
    ws.Range(ws.Cells(FIRST_ROW + 1, 6), ws.Cells(lastRow, 6)).Formula = _
        "=IF(OR(D" & FIRST_ROW + 1 & "="""",E" & FIRST_ROW + 1 & "=""""),""""," & _
        "(D" & FIRST_ROW + 1 & "-E" & FIRST_ROW + 1 & ")*100)"

    ' Sort worst return rate first
    With ws.Sort
        .SortFields.Clear
        .SortFields.Add Key:=ws.Range(ws.Cells(FIRST_ROW + 1, 4), ws.Cells(lastRow, 4)), _
                        Order:=xlDescending
        .SetRange ws.Range(ws.Cells(FIRST_ROW, 1), ws.Cells(lastRow, 7))
        .Header = xlYes
        .Apply
    End With

    ' Totals row (rate is re-computed from totals, never averaged)
    totalRow = lastRow + 1
    ws.Cells(totalRow, 1).Value = "Total"
    ws.Cells(totalRow, 2).Formula = "=SUM(B" & FIRST_ROW + 1 & ":B" & lastRow & ")"
    ws.Cells(totalRow, 3).Formula = "=SUM(C" & FIRST_ROW + 1 & ":C" & lastRow & ")"
    ws.Cells(totalRow, 4).Formula = "=IFERROR(C" & totalRow & "/B" & totalRow & ","""")"
    ws.Cells(totalRow, 7).Formula = "=SUM(G" & FIRST_ROW + 1 & ":G" & lastRow & ")"
    ws.Rows(totalRow).Font.Bold = True
    ws.Range(ws.Cells(totalRow, 1), ws.Cells(totalRow, 7)).Borders(xlEdgeTop).LineStyle = xlContinuous

    ' Number formats
    ws.Range(ws.Cells(FIRST_ROW + 1, 2), ws.Cells(totalRow, 3)).NumberFormat = "#,##0"
    ws.Range(ws.Cells(FIRST_ROW + 1, 4), ws.Cells(totalRow, 5)).NumberFormat = "0.0%"
    ws.Range(ws.Cells(FIRST_ROW + 1, 6), ws.Cells(totalRow, 6)).NumberFormat = "+0.0;-0.0;0.0"
    ws.Range(ws.Cells(FIRST_ROW + 1, 7), ws.Cells(totalRow, 7)).NumberFormat = "[$$-409]#,##0"   ' always US dollars, whatever the Mac's region

    ' Header style
    With ws.Range(ws.Cells(FIRST_ROW, 1), ws.Cells(FIRST_ROW, 7))
        .Font.Bold = True
        .Font.Color = RGB(255, 255, 255)
        .Interior.Color = RGB(35, 47, 62)
        .WrapText = True
    End With

    ' Conditional formatting
    Set rateCol = ws.Range(ws.Cells(FIRST_ROW + 1, 4), ws.Cells(lastRow, 4))
    With rateCol.FormatConditions.AddColorScale(ColorScaleType:=3)
        .ColorScaleCriteria(1).FormatColor.Color = RGB(99, 190, 123)   ' low = green
        .ColorScaleCriteria(2).FormatColor.Color = RGB(255, 235, 132)
        .ColorScaleCriteria(3).FormatColor.Color = RGB(248, 105, 107)  ' high = red
    End With

    ' Flag week-over-week changes only where the category has enough items to trust:
    ' with a handful of items, a single return moves the rate by 10+ points.
    ws.Calculate
    For i = FIRST_ROW + 1 To lastRow
        With ws.Cells(i, 6)
            If VarType(.Value) = vbDouble Then
                If ws.Cells(i, 2).Value < MIN_ITEMS_FLAG Then
                    .Font.Color = RGB(150, 150, 150)   ' too few items: grey
                ElseIf .Value > 1 Then
                    .Font.Color = RGB(192, 0, 0)       ' worse by more than 1 pp
                    .Font.Bold = True
                ElseIf .Value < -1 Then
                    .Font.Color = RGB(0, 128, 0)       ' better by more than 1 pp
                End If
            End If
        End With
    Next i

    ' Note under the table
    ws.Cells(totalRow + 2, 1).Value = _
        "Return rate = items returned / items delivered. Change = this week minus prior week, " & _
        "in percentage points. Red = worse by more than 1 pp. Grey = fewer than " & _
        MIN_ITEMS_FLAG & " items, too few to judge."
    ws.Cells(totalRow + 2, 1).Font.Italic = True

    ' Layout and print setup (one page, landscape)
    ws.Columns("A").ColumnWidth = 30
    ws.Columns("B:G").ColumnWidth = 15
    With ws.PageSetup
        .Orientation = xlLandscape
        .Zoom = False
        .FitToPagesWide = 1
        .FitToPagesTall = 1
        .PrintArea = ws.Range(ws.Cells(1, 1), ws.Cells(totalRow + 2, 7)).Address
    End With
End Sub

'------------------------------------------------------------------------------
' Helpers
'------------------------------------------------------------------------------

' Position of a column in the table by header name; clear error if missing.
Private Function ColIndex(lo As ListObject, header As String) As Long
    Dim col As ListColumn
    For Each col In lo.ListColumns
        If LCase$(Trim$(col.Name)) = LCase$(header) Then
            ColIndex = col.Index
            Exit Function
        End If
    Next col
    Err.Raise vbObjectError + 3, , "Column '" & header & "' not found in table '" & lo.Name & "'."
End Function

' Index of key in cats(1..n); appends it if new. (Cross-platform stand-in for a Dictionary.)
Private Function FindOrAdd(cats() As String, n As Long, key As String) As Long
    Dim i As Long
    For i = 1 To n
        If cats(i) = key Then
            FindOrAdd = i
            Exit Function
        End If
    Next i
    If n >= MAX_CATEGORIES Then
        Err.Raise vbObjectError + 4, , "More than " & MAX_CATEGORIES & " categories."
    End If
    n = n + 1
    cats(n) = key
    FindOrAdd = n
End Function

Private Function GetOrCreateSheet(sheetName As String) As Worksheet
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Worksheets(sheetName)
    On Error GoTo 0
    If ws Is Nothing Then
        Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
        ws.Name = sheetName
    End If
    Set GetOrCreateSheet = ws
End Function

' Safe numeric read: blanks and text count as 0. (Val() would break on comma-decimal locales.)
Private Function Num(v As Variant) As Double
    If IsNumeric(v) And Not IsEmpty(v) Then Num = CDbl(v)
End Function

' Finds the data table on any sheet, ignoring upper/lower case. If no table has that name
' but the workbook contains exactly one table, uses that one. Otherwise lists what it found.
Private Function FindTable(tableName As String) As ListObject
    Dim ws As Worksheet, t As ListObject, oneTable As ListObject
    Dim found As String, n As Long
    For Each ws In ThisWorkbook.Worksheets
        For Each t In ws.ListObjects
            If LCase$(t.Name) = LCase$(tableName) Then
                Set FindTable = t
                Exit Function
            End If
            n = n + 1
            Set oneTable = t
            found = found & vbCrLf & "  '" & t.Name & "' on sheet '" & ws.Name & "'"
        Next t
    Next ws
    If n = 1 Then
        Set FindTable = oneTable
        Exit Function
    End If
    If n = 0 Then found = vbCrLf & "  (no tables at all)"
    Err.Raise vbObjectError + 5, , "No table named '" & tableName & "'. Tables found:" & found & _
        vbCrLf & "Rename the data table to '" & tableName & "' (click in it > Table tab > Table Name)."
End Function

' Saves the sheet as a PDF and returns a message for the user. Excel for Mac may only write
' to folders it has been given access to, so it asks first; any failure is reported, not fatal.
Private Function ExportPdf(ws As Worksheet, pdfPath As String) As String
    On Error GoTo Failed
#If Mac Then
    If Not GrantAccessToMultipleFiles(Array(pdfPath)) Then
        ExportPdf = "PDF not saved: Excel was not given access to the folder."
        Exit Function
    End If
#End If
    ws.ExportAsFixedFormat Type:=xlTypePDF, Filename:=pdfPath
    ExportPdf = "PDF saved to:" & vbCrLf & pdfPath
    Exit Function
Failed:
    ExportPdf = "The report is built, but the PDF could not be saved (" & Err.Description & ")." & _
        vbCrLf & "Save it by hand: with the Report sheet open, File > Save As > File Format: PDF."
End Function
