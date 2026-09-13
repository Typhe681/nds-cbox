#include "Consoles.hpp"
#include "Shell.hpp"
#include "version.h"

#if defined(NDSH_THREADING) && defined(NDSH_CURL)
	#include "CurlMulti.hpp"
#endif

#include <dswifi9.h>
#include <fat.h>
#include <nds.h>
#ifndef __BLOCKSDS__
	#include <wfc.h>
#endif

static bool fsInit{}, wifiInit{};

bool Shell::wifiInitialized()
{
	return wifiInit;
}

bool Shell::fsInitialized()
{
	return fsInit;
}

void InitResources()
{
	auto &ostr = std::cout;

	if (isDSiMode())
		ostr << "DSi mode detected!\n";

	ostr << "initializing filesystem...";

	if (!fatInitDefault())
	{
		ostr << "\r\e[2K\e[91mfat init failed: filesystem commands will "
				"not work\n";
	}
	else
	{
		ostr << "\r\e[2K\e[92mfilesystem intialized!\n";
		fsInit = true;
	}

	ostr << "initializing wifi...";

#ifdef __BLOCKSDS__
	if (!Wifi_InitDefault(INIT_ONLY | WIFI_ATTEMPT_DSI_MODE))
#else
	if (!wlmgrInitDefault() || !wfcInit())
#endif
		ostr << "\r\e[2K\e[91mwifi init failed: networking commands will not "
				"work\e[39m\n";
	else
	{
		ostr << "\r\e[2K\e[92mwifi initialized!\n\e[39mautoconnecting...";
		wifiInit = true;
		void subcommand_autoconnect(std::ostream & ostr);
		subcommand_autoconnect(ostr);
	}

#if defined(NDSH_THREADING) && defined(NDSH_CURL)
	CurlMulti::Init();
#endif

	ostr << '\n';
}

int main()
{
	defaultExceptionHandler();
#ifndef __BLOCKSDS__
	tickInit();
#endif
	Consoles::Init();
	InitResources();

#if defined(NDSH_THREADING) && !defined(__BLOCKSDS__)
	threadGetSelf()->prio = THREAD_MIN_PRIO;
#endif

	Shell shell{0};
	shell.ProcessLine("lua cbox1.lua");

	while (pmMainLoop())
	{
#ifdef NDSH_THREADING
		threadYield();
#else
		swiWaitForVBlank();
#endif
	}
}
