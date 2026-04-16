import AppKit
import Foundation

/// Manages Word Add-in manifest installation / uninstallation for Microsoft Word on macOS.
///
/// The manifest XML is generated at install-time and placed in Word's
/// custom add-in Startup folder so that the add-in is available in the ribbon.
enum WordAddinInstaller {
    /// Target directory where Word looks for sideloaded manifests.
    /// Per Microsoft docs: ~/Library/Containers/com.microsoft.Word/Data/Documents/wef
    /// https://learn.microsoft.com/en-us/office/dev/add-ins/testing/sideload-an-office-add-in-on-mac
    static let manifestsDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Containers/com.microsoft.Word/Data/Documents/wef")
    }()

    /// Legacy path used before – cleaned up on install so stale manifests don't linger.
    private static let legacyManifestsDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Group Containers/UBF8T346G9.Office")
            .appendingPathComponent("User Content/Startup/Word/Manifests")
    }()

    static let manifestFileName = "SwiftLib.xml"

    static var manifestURL: URL {
        manifestsDir.appendingPathComponent(manifestFileName)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: manifestURL.path)
    }

    // MARK: - Install

    static func install() throws {
        let fm = FileManager.default

        // Remove manifest from legacy path if present
        let legacyManifest = legacyManifestsDir.appendingPathComponent(manifestFileName)
        if fm.fileExists(atPath: legacyManifest.path) {
            try? fm.removeItem(at: legacyManifest)
        }

        if !fm.fileExists(atPath: Self.manifestsDir.path) {
            try fm.createDirectory(at: Self.manifestsDir, withIntermediateDirectories: true)
        }

        let xml = Self.generateManifestXML()
        try xml.write(to: Self.manifestURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Uninstall

    static func uninstall() {
        try? FileManager.default.removeItem(at: manifestURL)
    }

    // MARK: - Reveal

    static func revealManifest() {
        if isInstalled {
            NSWorkspace.shared.selectFile(manifestURL.path, inFileViewerRootedAtPath: "")
        } else {
            NSWorkspace.shared.open(manifestsDir)
        }
    }

    // MARK: - Manifest XML generation

    private static func generateManifestXML() -> String {
        let baseURL = "http://127.0.0.1:\(WordAddinServer.port)"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <OfficeApp xmlns="http://schemas.microsoft.com/office/appforoffice/1.1"
                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   xmlns:bt="http://schemas.microsoft.com/office/officeappbasictypes/1.0"
                   xmlns:ov="http://schemas.microsoft.com/office/taskpaneappversionoverrides"
                   xsi:type="TaskPaneApp">
          <Id>a1b2c3d4-e5f6-7890-abcd-ef1234567890</Id>
          <Version>1.2.0.0</Version>
          <ProviderName>SwiftLib</ProviderName>
          <DefaultLocale>zh-CN</DefaultLocale>
          <DisplayName DefaultValue="SwiftLib 引文"/>
          <Description DefaultValue="在 Word 中插入和管理 SwiftLib 文献引用"/>
          <IconUrl DefaultValue="\(baseURL)/icon-32.png"/>
          <HighResolutionIconUrl DefaultValue="\(baseURL)/icon-80.png"/>
          <SupportUrl DefaultValue="\(baseURL)/taskpane.html"/>
          <Hosts>
            <Host Name="Document"/>
          </Hosts>
          <DefaultSettings>
            <SourceLocation DefaultValue="\(baseURL)/taskpane.html"/>
          </DefaultSettings>
          <Permissions>ReadWriteDocument</Permissions>
          <VersionOverrides xmlns="http://schemas.microsoft.com/office/taskpaneappversionoverrides" xsi:type="VersionOverridesV1_0">
            <Hosts>
              <Host xsi:type="Document">
                <DesktopFormFactor>
                  <FunctionFile resid="commandsURL"/>
                  <ExtensionPoint xsi:type="PrimaryCommandSurface">
                    <OfficeTab id="TabHome">
                      <Group id="SwiftLibGroup">
                        <Label resid="groupLabel"/>
                        <Icon>
                          <bt:Image size="16" resid="icon16"/>
                          <bt:Image size="32" resid="icon32"/>
                          <bt:Image size="80" resid="icon80"/>
                        </Icon>
                        <Control xsi:type="Button" id="insertCitationBtn">
                          <Label resid="insertCitLabel"/>
                          <Supertip>
                            <Title resid="insertCitLabel"/>
                            <Description resid="insertCitDesc"/>
                          </Supertip>
                          <Icon>
                            <bt:Image size="16" resid="icon16"/>
                            <bt:Image size="32" resid="icon32"/>
                            <bt:Image size="80" resid="icon80"/>
                          </Icon>
                          <Action xsi:type="ExecuteFunction">
                            <FunctionName>insertCitationCommand</FunctionName>
                          </Action>
                        </Control>
                        <Control xsi:type="Button" id="insertBibBtn">
                          <Label resid="insertBibLabel"/>
                          <Supertip>
                            <Title resid="insertBibLabel"/>
                            <Description resid="insertBibDesc"/>
                          </Supertip>
                          <Icon>
                            <bt:Image size="16" resid="icon16"/>
                            <bt:Image size="32" resid="icon32"/>
                            <bt:Image size="80" resid="icon80"/>
                          </Icon>
                          <Action xsi:type="ExecuteFunction">
                            <FunctionName>insertBibliography</FunctionName>
                          </Action>
                        </Control>
                        <Control xsi:type="Button" id="refreshBtn">
                          <Label resid="refreshLabel"/>
                          <Supertip>
                            <Title resid="refreshLabel"/>
                            <Description resid="refreshDesc"/>
                          </Supertip>
                          <Icon>
                            <bt:Image size="16" resid="icon16"/>
                            <bt:Image size="32" resid="icon32"/>
                            <bt:Image size="80" resid="icon80"/>
                          </Icon>
                          <Action xsi:type="ExecuteFunction">
                            <FunctionName>refreshAllCommand</FunctionName>
                          </Action>
                        </Control>
                        <Control xsi:type="Button" id="showPaneBtn">
                          <Label resid="showPaneLabel"/>
                          <Supertip>
                            <Title resid="showPaneLabel"/>
                            <Description resid="showPaneDesc"/>
                          </Supertip>
                          <Icon>
                            <bt:Image size="16" resid="icon16"/>
                            <bt:Image size="32" resid="icon32"/>
                            <bt:Image size="80" resid="icon80"/>
                          </Icon>
                          <Action xsi:type="ShowTaskpane">
                            <TaskpaneId>SwiftLibPane</TaskpaneId>
                            <SourceLocation resid="taskpaneURL"/>
                          </Action>
                        </Control>
                      </Group>
                    </OfficeTab>
                  </ExtensionPoint>
                </DesktopFormFactor>
              </Host>
            </Hosts>
            <Resources>
              <bt:Images>
                <bt:Image id="icon16" DefaultValue="\(baseURL)/icon-16.png"/>
                <bt:Image id="icon32" DefaultValue="\(baseURL)/icon-32.png"/>
                <bt:Image id="icon80" DefaultValue="\(baseURL)/icon-80.png"/>
              </bt:Images>
              <bt:Urls>
                <bt:Url id="taskpaneURL" DefaultValue="\(baseURL)/taskpane.html"/>
                <bt:Url id="commandsURL" DefaultValue="\(baseURL)/commands.html"/>
              </bt:Urls>
              <bt:ShortStrings>
                <bt:String id="groupLabel" DefaultValue="SwiftLib"/>
                <bt:String id="insertCitLabel" DefaultValue="插入引文"/>
                <bt:String id="insertBibLabel" DefaultValue="插入参考文献"/>
                <bt:String id="refreshLabel" DefaultValue="刷新引文"/>
                <bt:String id="showPaneLabel" DefaultValue="SwiftLib 面板"/>
              </bt:ShortStrings>
              <bt:LongStrings>
                <bt:String id="insertCitDesc" DefaultValue="在光标处插入引文"/>
                <bt:String id="insertBibDesc" DefaultValue="在光标处插入参考文献表"/>
                <bt:String id="refreshDesc" DefaultValue="刷新文档中所有引文与参考文献"/>
                <bt:String id="showPaneDesc" DefaultValue="显示 SwiftLib 侧边栏"/>
              </bt:LongStrings>
            </Resources>
          </VersionOverrides>
        </OfficeApp>
        """
    }
}
