# siditran - Simple Discord Translator Bot
![Language](https://img.shields.io/github/languages/top/zpeller/siditran)
![Size](https://img.shields.io/github/languages/code-size/zpeller/siditran)
![Issues](https://img.shields.io/github/issues/zpeller/siditran)
![Size](https://img.shields.io/github/stars/zpeller/siditran)

## NOTE: The project is in an active development phase, so even though the repository version should mostly work, it might have issues.

SiDiTran is a self-hosted Discord translator bot. The intention is to keep the bot simple but stable in the supported functions. Initially three major functions are supported: manual, automatic (live) and flag reaction translations.

The project started as a fork and major rewrite of [JohanSanSebastian/Translator101](https://github.com/JohanSanSebastian/Translator101), as [zpeller/SiDiTran.py](https://github.com/zpeller/SiDiTran.py) including an upgrade to discord.py's successor [Pycord](https://github.com/Pycord-Development/pycord) and Google Translator API v3. That version is mostly complete regarding functionality and stability, although it might have unknown issues yet. However as I prefer Ruby over Python, I've started to port the whole project to Ruby, based on the library `discordrb`, and this is the result. **NOTE: The porting is IN PROGRESS, the backends work (discord connection, google translator, config handling, etc), but currently only a handful of commands are usable on Discord as bot commands.**

## Installation and running
0. I recommend using ruby-virtualenv to keep your gems close to your package dir and nicely separated from each other:
```
gem install --user-install ruby-virtualenv
~/.gem/ruby/$(ruby -e 'puts RUBY_VERSION[0..-2]+"0"')/bin/ruby-virtualenv venv_siditran  # might be at different path
. venv_siditran/bin/activate 
```

1. Install all the necessary gems, using `bundle`

2. Create a Discord project, generate a token and get a client ID. You can start at the [Discord Application](https://discord.com/developers/applications) main page, or read [Discord Getting Started](https://discord.com/developers/docs/getting-started). You can invite your bot to your server via [https://discordapp.com/oauth2/authorize?permissions=275482274880&scope=bot&client_id=YOUR_CLIENT_ID](https://discordapp.com/oauth2/authorize?permissions=275482274880&scope=bot&client_id=YOUR_CLIENT_ID) (Change YOUR_CLIENT_ID to your own Discord client id!)

3. This bot uses Google Translate API v3 aka Cloud Translation Advanced edition. You have to setup your own developer access to this API however, using OAuth2. Signing up is free, and you can have translations up to 500,000 characters/month for free. You can get more if you pay for it. The free quota is not enough however to serve several Discord servers, so keep your credentials safe. You can get help creating your access from the [cloud translate setup docs](https://cloud.google.com/translate/docs/setup). You will have to get a project id, and your credentials set up. At the end `gcloud projects list`, `gcloud auth list` and `gcloud auth print-access-token` commands should give you reasonable outputs.

4. To run the bot you also need to create a file called `.env` in the project directory and setup the variables in it to your needs. You will have to change `DISCORD_TOKEN` to your own bot token, and `GOOGLE_TRANSLATE_PROJECT_ID` to your Google project id. You can start by copying `.env.example` to `.env`.

5. Once all done, run the bot:
```bash
ruby siditran.rb
```

6. Issue the command `/help`, `/languages` or `/autotranslate en` on your welcome channel to test the bot.

7. If something is wrong, try setting `DEBUG` to `1` and `DEBUG_LEVEL` to `INFO` or `DEBUG`.

## Testing
The bot has been tested on Debian Linux 12 (bookworm), test results from other systems are welcome.

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License
[GNU GPLv3](https://choosealicense.com/licenses/gpl-3.0/)
