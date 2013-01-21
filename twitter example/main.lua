require "twitter"

print("Native IOS5+ Twitter test")

-- LIST OF EVENTS --

twitter:addEventListener(Event.TWEET_COMPLETED, function()
	print("TWEET_COMPLETED")
end)

twitter:addEventListener(Event.TWEET_FAILED, function()
	print("TWEET_FAILED") -- then show video
end)

-- LIST OF API --

-- send tweet (text, imagepath) imagepath could be ignored
twitter:tweet("Lorem ipsum dolores sit amet www.google.com" , "image.png") 
