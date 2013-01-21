/*
 
 This code is MIT licensed, see http://www.opensource.org/licenses/mit-license.php
 (C) 2013 Nightspade
 
 */

#include "gideros.h"
#include "lua.h"
#include "lauxlib.h"
#import "Twitter/TWTweetComposeViewController.h"

// some Lua helper functions
#ifndef abs_index
#define abs_index(L, i) ((i) > 0 || (i) <= LUA_REGISTRYINDEX ? (i) : lua_gettop(L) + (i) + 1)
#endif

static void luaL_newweaktable(lua_State *L, const char *mode)
{
	lua_newtable(L);			// create table for instance list
	lua_pushstring(L, mode);
	lua_setfield(L, -2, "__mode");	  // set as weak-value table
	lua_pushvalue(L, -1);             // duplicate table
	lua_setmetatable(L, -2);          // set itself as metatable
}

static void luaL_rawgetptr(lua_State *L, int idx, void *ptr)
{
	idx = abs_index(L, idx);
	lua_pushlightuserdata(L, ptr);
	lua_rawget(L, idx);
}

static void luaL_rawsetptr(lua_State *L, int idx, void *ptr)
{
	idx = abs_index(L, idx);
	lua_pushlightuserdata(L, ptr);
	lua_insert(L, -2);
	lua_rawset(L, idx);
}

enum
{
	GTWITTER_TWEET_COMPLETED,
    GTWITTER_TWEET_FAILED
};

static const char *TWEET_COMPLETED = "tweetCompleted";
static const char *TWEET_FAILED = "tweetFailed";

static char keyWeak = ' ';

class GTwitterPlugin : public GEventDispatcherProxy
{
public:
    GTwitterPlugin(lua_State *L) : L(L)
	{}
    
	~GTwitterPlugin()
	{}
    
    void tweet(const char* text, const char* imagePath)
    {
        NSString* message = [NSString stringWithUTF8String:text];
        Class twitterClass = NSClassFromString(@"TWTweetComposeViewController");   // for backward compatibility
        if (twitterClass) {
            TWTweetComposeViewController *tweetViewController = [[TWTweetComposeViewController alloc] init];
                
            [tweetViewController setInitialText:message];
                
            if (imagePath != nil) {
                NSString* path = [NSString stringWithUTF8String:g_pathForFile(imagePath)];
                UIImage* img = [UIImage imageWithContentsOfFile:path];
                [tweetViewController addImage:img]; // add image. just as it says
            }
            
            [g_getRootViewController() presentViewController:tweetViewController animated:YES completion:nil];
                
            // check on this part using blocks
            tweetViewController.completionHandler = ^(TWTweetComposeViewControllerResult res) {
                if (res == TWTweetComposeViewControllerResultDone) {
                    // Twitter sent successfully.
                    dispatchEvent(GTWITTER_TWEET_COMPLETED, NULL);
                } else if (res == TWTweetComposeViewControllerResultCancelled) {
                    // Tweet cancelled.
                    dispatchEvent(GTWITTER_TWEET_FAILED, NULL);
                }
                [tweetViewController dismissModalViewControllerAnimated:YES];
                [tweetViewController release];
            };
        } else {
            //under iOS5
            
            //URL encode
            NSMutableString *output = [NSMutableString string];
            const unsigned char *source = (const unsigned char *)[message UTF8String];
            int sourceLen = strlen((const char *)source);
            for (int i = 0; i < sourceLen; ++i) {
                const unsigned char thisChar = source[i];
                if (thisChar == ' '){
                    [output appendString:@"%20"];
                } else if (thisChar == '.' || thisChar == '-' || thisChar == '_' || thisChar == '~' ||
                           (thisChar >= 'a' && thisChar <= 'z') ||
                           (thisChar >= 'A' && thisChar <= 'Z') ||
                           (thisChar >= '0' && thisChar <= '9')) {
                    [output appendFormat:@"%c", thisChar];
                } else {
                    [output appendFormat:@"%%%02X", thisChar];
                }
            }
        
            NSMutableString *url = [NSMutableString stringWithString:@"twitter://post?message="];
            [url appendString:output];
            if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:url]])
            {
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
            } else {
                url = [NSMutableString stringWithString:@"https://twitter.com/intent/tweet?text="];
                [url appendString:output];
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
            }
            
            // whatever happens, dispatch tweet success
            dispatchEvent(GTWITTER_TWEET_COMPLETED, NULL);
        }
    }
    
	void dispatchEvent(int type, void *event)
	{
		luaL_rawgetptr(L, LUA_REGISTRYINDEX, &keyWeak);
		luaL_rawgetptr(L, -1, this);
        
		if (lua_isnil(L, -1))
		{
			lua_pop(L, 2);
			return;
		}
        
		lua_getfield(L, -1, "dispatchEvent");
        
		lua_pushvalue(L, -2);
        
		lua_getglobal(L, "Event");
		lua_getfield(L, -1, "new");
		lua_remove(L, -2);
        
		switch (type)
		{
            case GTWITTER_TWEET_COMPLETED:
                lua_pushstring(L, TWEET_COMPLETED);
                break;
            case GTWITTER_TWEET_FAILED:
                lua_pushstring(L, TWEET_FAILED);
                break;
		}
        
		lua_call(L, 1, 1);
        
		lua_call(L, 2, 0);
        
		lua_pop(L, 2);
	}
    
private:
	lua_State *L;
};

static int destruct(lua_State* L)
{
	void *ptr =*(void**)lua_touserdata(L, 1);
	GReferenced* object = static_cast<GReferenced*>(ptr);
	GTwitterPlugin *instance = static_cast<GTwitterPlugin*>(object->proxy());
	instance->unref();
    
	return 0;
}

static int tweet(lua_State *L)
{
	GReferenced *object = static_cast<GReferenced*>(g_getInstance(L, "Twitter", 1));
	GTwitterPlugin *instance = static_cast<GTwitterPlugin*>(object->proxy());
	
	const char *text = lua_tostring(L, 2);
    const char *imagePath = lua_tostring(L, 3);
	
	instance->tweet(text, imagePath);
	
	return 0;
}


static int loader(lua_State *L)
{
	const luaL_Reg functionList[] = {
		{"tweet", tweet},
		{NULL, NULL}
	};
    
    g_createClass(L, "Twitter", "EventDispatcher", NULL, destruct, functionList);
    
    // create a weak table in LUA_REGISTRYINDEX that can be accessed with the address of keyWeak
	luaL_newweaktable(L, "v");
	luaL_rawsetptr(L, LUA_REGISTRYINDEX, &keyWeak);
    
    lua_getglobal(L, "Event");
	lua_pushstring(L, TWEET_COMPLETED);
	lua_setfield(L, -2, "TWEET_COMPLETED");
	lua_pushstring(L, TWEET_FAILED);
	lua_setfield(L, -2, "TWEET_FAILED");
	lua_pop(L, 1);
    
	GTwitterPlugin *instance = new GTwitterPlugin(L);
	g_pushInstance(L, "Twitter", instance->object());
    
	luaL_rawgetptr(L, LUA_REGISTRYINDEX, &keyWeak);
	lua_pushvalue(L, -2);
	luaL_rawsetptr(L, -2, instance);
	lua_pop(L, 1);
    
	lua_pushvalue(L, -1);
	lua_setglobal(L, "twitter");
    
    return 1;
}

static void g_initializePlugin(lua_State *L)
{
    lua_getglobal(L, "package");
	lua_getfield(L, -1, "preload");
    
	lua_pushcfunction(L, loader);
	lua_setfield(L, -2, "twitter");
    
	lua_pop(L, 2);
}

static void g_deinitializePlugin(lua_State *L)
{
    
}

REGISTER_PLUGIN("Twitter", "2013.1")
