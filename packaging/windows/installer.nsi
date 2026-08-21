; NEXUS Windows installer (NSIS)
; Built by CI: makensis /DVERSION=x.y.z /DSRC_DIR=build/windows /DOUT_FILE=dist/NEXUS-Setup-x.y.z.exe installer.nsi

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef SRC_DIR
  !define SRC_DIR "..\..\build\windows"
!endif
!ifndef OUT_FILE
  !define OUT_FILE "NEXUS-Setup.exe"
!endif

Name "NEXUS"
OutFile "${OUT_FILE}"
; Per-user install under %LocalAppData% — no admin/UAC prompt required.
InstallDir "$LOCALAPPDATA\NEXUS"
InstallDirRegKey HKCU "Software\NEXUS" "Install_Dir"
RequestExecutionLevel user
SetCompressor /SOLID lzma

Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Section "NEXUS (requis)"
  SectionIn RO
  SetOutPath "$INSTDIR"
  File "${SRC_DIR}\NEXUS.exe"
  File "${SRC_DIR}\NEXUS.pck"

  WriteRegStr HKCU "Software\NEXUS" "Install_Dir" "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\NEXUS"
  CreateShortcut "$SMPROGRAMS\NEXUS\NEXUS.lnk" "$INSTDIR\NEXUS.exe"
  CreateShortcut "$SMPROGRAMS\NEXUS\Désinstaller.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\NEXUS.lnk" "$INSTDIR\NEXUS.exe"

  ; HKCU (not HKLM) so uninstall registration doesn't need admin either —
  ; still shows up fine in "Apps & features" for the current user.
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NEXUS" "DisplayName" "NEXUS"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NEXUS" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NEXUS" "DisplayVersion" "${VERSION}"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\NEXUS.exe"
  Delete "$INSTDIR\NEXUS.pck"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  Delete "$SMPROGRAMS\NEXUS\NEXUS.lnk"
  Delete "$SMPROGRAMS\NEXUS\Désinstaller.lnk"
  RMDir "$SMPROGRAMS\NEXUS"
  Delete "$DESKTOP\NEXUS.lnk"

  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NEXUS"
  DeleteRegKey HKCU "Software\NEXUS"
SectionEnd
