; SPDX-FileCopyrightText: 2026 Siegefall contributors
; SPDX-License-Identifier: MIT
;
; Windows installer, built by scripts/package.sh nsis. Per-user install (no
; administrator rights), Start-menu shortcut, optional desktop shortcut, and
; an uninstaller in Apps & features. Saves are only removed when the player
; ticks the box in the uninstaller.
;
; makensis is given these on the command line:
;   APP_NAME APP_ID APP_SLUG APP_VERSION APP_DEVELOPER APP_HOMEPAGE
;   SRC_DIR (the Windows export) OUT_FILE ICON LICENSE_FILE

Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"

Name "${APP_NAME}"
OutFile "${OUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP_NAME}"
InstallDirRegKey HKCU "Software\${APP_NAME}" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
ManifestDPIAware true
BrandingText "${APP_NAME} ${APP_VERSION}"

VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "CompanyName" "${APP_DEVELOPER}"
VIAddVersionKey "FileDescription" "${APP_NAME} installer"
VIAddVersionKey "LegalCopyright" "${APP_DEVELOPER}"

!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"

!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_COMPONENTSPAGE_NODESC
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_NAME}.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Play ${APP_NAME} now"

!insertmacro MUI_PAGE_LICENSE "${LICENSE_FILE}"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_COMPONENTS
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Section "!${APP_NAME}" SecGame
	SectionIn RO
	SetOutPath "$INSTDIR"
	File "${SRC_DIR}/${APP_NAME}.exe"
	File "${SRC_DIR}/*.dll"
	File "${SRC_DIR}/README.txt"
	File "${SRC_DIR}/LICENSE.txt"
	File "${SRC_DIR}/THIRD-PARTY-NOTICES.txt"
	WriteUninstaller "$INSTDIR\Uninstall.exe"
	CreateShortcut "$SMPROGRAMS\${APP_NAME}.lnk" "$INSTDIR\${APP_NAME}.exe"

	WriteRegStr HKCU "Software\${APP_NAME}" "InstallDir" "$INSTDIR"
	WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${APP_NAME}"
	WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${APP_VERSION}"
	WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "${APP_DEVELOPER}"
	WriteRegStr HKCU "${UNINST_KEY}" "URLInfoAbout" "${APP_HOMEPAGE}"
	WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${APP_NAME}.exe"
	WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
	WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
	WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
	WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
	WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
	${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
	IntFmt $0 "0x%08X" $0
	WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "Desktop shortcut" SecDesktop
	CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_NAME}.exe"
SectionEnd

Section "un.${APP_NAME}" UnSecGame
	SectionIn RO
	Delete "$INSTDIR\${APP_NAME}.exe"
	Delete "$INSTDIR\*.dll"
	Delete "$INSTDIR\README.txt"
	Delete "$INSTDIR\LICENSE.txt"
	Delete "$INSTDIR\THIRD-PARTY-NOTICES.txt"
	Delete "$INSTDIR\Uninstall.exe"
	RMDir "$INSTDIR"
	Delete "$SMPROGRAMS\${APP_NAME}.lnk"
	Delete "$DESKTOP\${APP_NAME}.lnk"
	DeleteRegKey HKCU "${UNINST_KEY}"
	DeleteRegKey HKCU "Software\${APP_NAME}"
SectionEnd

Section /o "un.Also delete my saves, castles and settings" UnSecData
	RMDir /r "$APPDATA\${APP_SLUG}"
SectionEnd
