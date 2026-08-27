// Runtime Pack Verified - public-domain source; see the repository LICENSE.
// Enables the OS-owned NetFx3 capability by invoking only the system DISM binary.
#include <windows.h>

#include <iostream>
#include <string>
#include <vector>

namespace {

std::wstring GetSystemDismPath() {
    const UINT required = GetSystemDirectoryW(nullptr, 0);
    if (required == 0) {
        return {};
    }

    std::wstring directory(required, L'\0');
    if (GetSystemDirectoryW(directory.data(), required) == 0) {
        return {};
    }
    directory.resize(required - 1);
    return directory + L"\\dism.exe";
}

std::wstring GetLogPath() {
    const DWORD required = GetTempPathW(0, nullptr);
    if (required == 0) {
        return L"RuntimePack-NetFx3.log";
    }

    std::wstring directory(required, L'\0');
    if (GetTempPathW(required, directory.data()) == 0) {
        return L"RuntimePack-NetFx3.log";
    }
    directory.resize(required - 1);
    return directory + L"RuntimePack-NetFx3.log";
}

void WriteLog(HANDLE log, const std::wstring& message) {
    const std::wstring line = message + L"\r\n";
    DWORD bytesWritten = 0;
    WriteFile(log, line.data(), static_cast<DWORD>(line.size() * sizeof(wchar_t)), &bytesWritten, nullptr);
}

int EnableNetFx3() {
    const std::wstring dismPath = GetSystemDismPath();
    if (dismPath.empty() || GetFileAttributesW(dismPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
        std::wcerr << L"Windows DISM was not found." << std::endl;
        return ERROR_FILE_NOT_FOUND;
    }

    const std::wstring logPath = GetLogPath();
    HANDLE log = CreateFileW(logPath.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (log == INVALID_HANDLE_VALUE) {
        std::wcerr << L"Unable to create the NetFx3 servicing log." << std::endl;
        return GetLastError();
    }

    WriteLog(log, L"Runtime Pack Verified: enabling NetFx3 using Windows servicing.");
    WriteLog(log, L"Command is fixed by the helper: DISM /Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart");

    std::wstring commandLine = L"\"" + dismPath + L"\" /Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart";
    std::vector<wchar_t> mutableCommand(commandLine.begin(), commandLine.end());
    mutableCommand.push_back(L'\0');

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdOutput = log;
    startup.hStdError = log;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    PROCESS_INFORMATION process{};

    const BOOL launched = CreateProcessW(
        dismPath.c_str(), mutableCommand.data(), nullptr, nullptr, TRUE,
        CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process);
    if (!launched) {
        const DWORD error = GetLastError();
        WriteLog(log, L"Failed to launch the system DISM executable. Error: " + std::to_wstring(error));
        CloseHandle(log);
        return static_cast<int>(error);
    }

    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD exitCode = ERROR_GEN_FAILURE;
    GetExitCodeProcess(process.hProcess, &exitCode);
    WriteLog(log, L"DISM exit code: " + std::to_wstring(exitCode));
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    CloseHandle(log);

    if (exitCode != ERROR_SUCCESS && exitCode != ERROR_SUCCESS_REBOOT_REQUIRED && exitCode != ERROR_SUCCESS_RESTART_REQUIRED) {
        std::wcerr << L"Windows could not enable .NET Framework 3.5. See " << logPath << std::endl;
    }
    return static_cast<int>(exitCode);
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR commandLine, int) {
    if (commandLine != nullptr && wcsstr(commandLine, L"--self-test") != nullptr) {
        const std::wstring dismPath = GetSystemDismPath();
        return (!dismPath.empty() && GetFileAttributesW(dismPath.c_str()) != INVALID_FILE_ATTRIBUTES)
            ? ERROR_SUCCESS
            : ERROR_FILE_NOT_FOUND;
    }
    if (commandLine != nullptr && (wcsstr(commandLine, L"/?") != nullptr || wcsstr(commandLine, L"--help") != nullptr)) {
        MessageBoxW(nullptr,
            L"Enables the Windows NetFx3 capability using the OS servicing stack.\n\n"
            L"It uses local component files, an administrator-configured repair source, or Windows Update.\n"
            L"This helper accepts no source path and never downloads Windows media itself.",
            L"Runtime Pack Verified - .NET Framework 3.5", MB_OK | MB_ICONINFORMATION);
        return ERROR_SUCCESS;
    }
    return EnableNetFx3();
}
