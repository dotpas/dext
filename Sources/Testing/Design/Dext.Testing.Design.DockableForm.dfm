object FormDextTestRunner: TFormDextTestRunner
  Left = 0
  Top = 0
  Caption = 'Dext Test Explorer'
  ClientHeight = 650
  ClientWidth = 571
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Segoe UI'
  Font.Style = []
  TextHeight = 13
  object NameSplitter: TSplitter
    Left = 0
    Top = 330
    Width = 571
    Height = 3
    Cursor = crVSplit
    Align = alBottom
    ExplicitTop = 300
    ExplicitWidth = 350
  end
  object SessionsPageControl: TPageControl
    Left = 0
    Top = 84
    Width = 571
    Height = 246
    ActivePage = DefaultSessionTabSheet
    Align = alClient
    TabOrder = 0
    object DefaultSessionTabSheet: TTabSheet
      Caption = 'Tests'
      object TestsTreeView: TTreeView
        Left = 0
        Top = 0
        Width = 563
        Height = 218
        Align = alClient
        Indent = 19
        ReadOnly = True
        TabOrder = 0
        OnDblClick = TestsTreeViewDblClick
      end
    end
  end
  object DetailsPanel: TPanel
    Left = 0
    Top = 333
    Width = 571
    Height = 317
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object DetailsPageControl: TPageControl
      Left = 0
      Top = 32
      Width = 571
      Height = 285
      ActivePage = ConsoleTab
      Align = alClient
      TabOrder = 0
      object InspectorTab: TTabSheet
        Caption = 'Test Inspector'
        object InspectorScroll: TScrollBox
          Left = 0
          Top = 0
          Width = 563
          Height = 257
          Align = alClient
          BorderStyle = bsNone
          TabOrder = 0
          ExplicitHeight = 162
          object InfoPanel: TPanel
            Left = 0
            Top = 0
            Width = 563
            Height = 98
            Align = alTop
            BevelOuter = bvNone
            ParentColor = True
            TabOrder = 0
            object TestNameLabel: TLabel
              Left = 6
              Top = 6
              Width = 130
              Height = 13
              Caption = 'Test Name: Select a test...'
              Font.Charset = DEFAULT_CHARSET
              Font.Color = clWindowText
              Font.Height = -11
              Font.Name = 'Segoe UI'
              Font.Style = [fsBold]
              ParentFont = False
            end
            object StatusLabel: TLabel
              Left = 6
              Top = 24
              Width = 57
              Height = 13
              Caption = 'Status: Idle'
            end
            object LocationLabel: TLabel
              Left = 6
              Top = 42
              Width = 69
              Height = 13
              Caption = 'Location: N/A'
            end
            object DurationLabel: TLabel
              Left = 6
              Top = 60
              Width = 71
              Height = 13
              Caption = 'Duration: N/A'
            end
            object ErrorHeaderLabel: TLabel
              Left = 6
              Top = 78
              Width = 100
              Height = 13
              Caption = 'Errors / Stack Trace:'
              Font.Charset = DEFAULT_CHARSET
              Font.Color = clWindowText
              Font.Height = -11
              Font.Name = 'Segoe UI'
              Font.Style = [fsBold]
              ParentFont = False
            end
          end
          object ErrorMemo: TMemo
            Left = 0
            Top = 98
            Width = 563
            Height = 45
            Align = alTop
            ReadOnly = True
            ScrollBars = ssBoth
            TabOrder = 1
          end
        end
      end
      object ConfigTab: TTabSheet
        Caption = 'Configurations'
        ImageIndex = 1
        object ConfigScroll: TScrollBox
          Left = 0
          Top = 0
          Width = 563
          Height = 257
          Align = alClient
          BorderStyle = bsNone
          TabOrder = 0
          ExplicitHeight = 162
          object CustomParamsLabel: TLabel
            Left = 10
            Top = 10
            Width = 180
            Height = 13
            Caption = 'Custom Command Line Parameters:'
          end
          object CustomParamsEdit: TEdit
            Left = 10
            Top = 28
            Width = 350
            Height = 21
            TabOrder = 0
          end
          object RunOnSaveCheckBox: TCheckBox
            Left = 10
            Top = 65
            Width = 200
            Height = 17
            Caption = 'Run tests automatically on Save'
            TabOrder = 1
          end
          object RunOnIdleCheckBox: TCheckBox
            Left = 10
            Top = 90
            Width = 200
            Height = 17
            Caption = 'Run tests automatically on Idle'
            TabOrder = 2
          end
          object EnabledCheckBox: TCheckBox
            Left = 10
            Top = 115
            Width = 200
            Height = 17
            Caption = 'Enable Dext Test Explorer'
            TabOrder = 3
          end
        end
      end
      object ConsoleTab: TTabSheet
        Caption = 'Console Log'
        ImageIndex = 2
        object DetailsMemo: TRichEdit
          Left = 0
          Top = 0
          Width = 563
          Height = 257
          Align = alClient
          Font.Charset = ANSI_CHARSET
          Font.Color = clWindowText
          Font.Height = -12
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          ReadOnly = True
          ScrollBars = ssBoth
          TabOrder = 0
        end
      end
    end
    object SummaryPanel: TPanel
      AlignWithMargins = True
      Left = 1
      Top = 1
      Width = 569
      Height = 30
      Margins.Left = 1
      Margins.Top = 1
      Margins.Right = 1
      Margins.Bottom = 1
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 1
      object SummaryTotalLabel: TLabel
        AlignWithMargins = True
        Left = 3
        Top = 6
        Width = 55
        Height = 13
        Margins.Top = 6
        Margins.Bottom = 6
        Align = alLeft
        Caption = 'Total: 9999'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentFont = False
      end
      object SummarySelectedLabel: TLabel
        AlignWithMargins = True
        Left = 64
        Top = 6
        Width = 73
        Height = 13
        Margins.Top = 6
        Margins.Bottom = 6
        Align = alLeft
        Caption = 'Selected: 9999'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -11
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object SummarySuccessLabel: TLabel
        AlignWithMargins = True
        Left = 143
        Top = 6
        Width = 66
        Height = 13
        Margins.Top = 6
        Margins.Bottom = 6
        Align = alLeft
        Caption = 'Passed: 9999'
        Color = clBtnFace
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGreen
        Font.Height = -11
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentColor = False
        ParentFont = False
      end
      object SummaryFailedLabel: TLabel
        AlignWithMargins = True
        Left = 215
        Top = 6
        Width = 61
        Height = 13
        Margins.Top = 6
        Margins.Bottom = 6
        Align = alLeft
        Caption = 'Failed: 9999'
        Color = clBtnFace
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clRed
        Font.Height = -11
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentColor = False
        ParentFont = False
      end
      object SummarySkippedLabel: TLabel
        AlignWithMargins = True
        Left = 282
        Top = 6
        Width = 72
        Height = 13
        Margins.Top = 6
        Margins.Bottom = 6
        Align = alLeft
        Caption = 'Skipped: 9999'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -11
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object SummaryTimeLabel: TLabel
        AlignWithMargins = True
        Left = 360
        Top = 6
        Width = 87
        Height = 13
        Margins.Top = 6
        Margins.Bottom = 6
        Align = alLeft
        Caption = 'Time: 9999.9999s'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentFont = False
      end
      object SummaryTotalTimeLabel: TLabel
        AlignWithMargins = True
        Left = 453
        Top = 6
        Width = 112
        Height = 13
        Margins.Top = 6
        Margins.Bottom = 6
        Align = alLeft
        Caption = 'Total Time: 9999.9999s'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -11
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
    end
  end
  object ButtonsPanel: TPanel
    Left = 0
    Top = 35
    Width = 571
    Height = 31
    Margins.Left = 0
    Margins.Right = 0
    Margins.Bottom = 6
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 2
    object RefreshButton: TButton
      AlignWithMargins = True
      Left = 3
      Top = 3
      Width = 80
      Height = 25
      Align = alLeft
      Caption = 'Refresh'
      TabOrder = 0
      OnClick = RefreshButtonClick
    end
    object RunAllButton: TButton
      AlignWithMargins = True
      Left = 89
      Top = 3
      Width = 85
      Height = 25
      Align = alLeft
      Caption = 'Run All'
      TabOrder = 1
      OnClick = RunAllButtonClick
    end
    object RunSelectedButton: TButton
      AlignWithMargins = True
      Left = 180
      Top = 3
      Width = 85
      Height = 25
      Align = alLeft
      Caption = 'Selected'
      TabOrder = 2
      OnClick = RunSelectedButtonClick
    end
    object StopButton: TButton
      AlignWithMargins = True
      Left = 271
      Top = 3
      Width = 50
      Height = 25
      Align = alLeft
      Caption = 'Stop'
      TabOrder = 3
      OnClick = StopButtonClick
    end
    object ActionsButton: TButton
      AlignWithMargins = True
      Left = 543
      Top = 3
      Width = 25
      Height = 25
      Align = alRight
      Caption = '...'
      TabOrder = 4
      OnClick = ActionsButtonClick
    end
  end
  object ProjectsComboBox: TComboBox
    AlignWithMargins = True
    Left = 3
    Top = 7
    Width = 565
    Height = 21
    Margins.Top = 7
    Margins.Bottom = 7
    Align = alTop
    Style = csDropDownList
    TabOrder = 3
    OnChange = ProjectsComboBoxChange
    ExplicitWidth = 618
  end
  object ProgressPanel: TPanel
    Left = 0
    Top = 66
    Width = 571
    Height = 18
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 4
    Visible = False
    object ProgressLabel: TLabel
      Left = 0
      Top = 0
      Width = 2
      Height = 12
      Align = alLeft
      Alignment = taCenter
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -9
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Layout = tlCenter
    end
    object ProgressBar: TProgressBar
      Left = 2
      Top = 0
      Width = 569
      Height = 18
      Align = alClient
      TabOrder = 0
    end
  end
  object ActionsPopupMenu: TPopupMenu
    Left = 396
    Top = 122
    object EnableDisableTestExplorerMenuItem: TMenuItem
      Caption = 'Disable Test Explorer'
      Hint = 'Disable Test Explorer'
    end
    object CreateaNewSessionMenuItem: TMenuItem
      Caption = 'Create a New Session'
    end
    object ClearMenuItem: TMenuItem
      Caption = 'Clear Tests and Console Log'
      Hint = 'Clear Tests and Console Log'
    end
    object ClearSeparator: TMenuItem
      Caption = '-'
    end
    object GroupByClassMenuItem: TMenuItem
      Caption = 'Group by Code Structure'
      GroupIndex = 10
      RadioItem = True
    end
    object GroupByTestStatusMenuItem: TMenuItem
      Caption = 'Group by Test Status'
      GroupIndex = 10
      RadioItem = True
    end
    object LayoutSeparator: TMenuItem
      Caption = '-'
      GroupIndex = 10
    end
    object SplitBottomLayoutMenuItem: TMenuItem
      Caption = 'Split Bottom Layout'
      GroupIndex = 20
      RadioItem = True
    end
    object SplitRightLayoutMenuItem: TMenuItem
      Caption = 'Split Right Layout'
      GroupIndex = 20
      RadioItem = True
    end
    object TabbedLayoutMenuItem: TMenuItem
      Caption = 'Tabbed Layout'
      GroupIndex = 20
      Hint = 'Tabbed Layout at Bottom'
      RadioItem = True
    end
    object ExportSeparator: TMenuItem
      Caption = '-'
      GroupIndex = 20
    end
    object ExportToJUnitXmlMenutem: TMenuItem
      Caption = 'Export to JUnit XML'
      GroupIndex = 20
      Hint = 'Export test execution report to JUnit XML'
    end
    object ExportToXUnitXMLMenutem: TMenuItem
      Caption = 'Export to XUnit XML'
      GroupIndex = 20
      Hint = 'Export test execution report to XUnit XML'
    end
    object ExportToJsonMenutem: TMenuItem
      Caption = 'Export to JSON'
      GroupIndex = 20
      Hint = 'Export test execution report to JSON'
    end
    object ExportToSonarQubeXmlMenutem: TMenuItem
      Caption = 'Export to SonarQube XML'
      GroupIndex = 20
      Hint = 'Export test execution report to SonarQube XML'
    end
    object ExportToHtmlReportMenuItem: TMenuItem
      Caption = 'Export to HTML Report'
      GroupIndex = 20
      Hint = 'Export test execution report to HTML Report'
    end
  end
end
