require 'bundler/setup'
Bundler.require
require 'sinatra/reloader' if development?
require './models.rb'
require 'cgi'
require 'json'
require 'line/bot'

before do 
    if request.path_info == '/sei_san'
        def client
            @client ||= Line::Bot::Client.new { |config|
                config.channel_secret = ENV['LINE_CHANNEL_SECRET_SEISAN']
                config.channel_token = ENV['LINE_CHANNEL_TOKEN_SEISAN']
            }
        end
    elsif request.path_info == '/list'
        def client
            @client ||= Line::Bot::Client.new { |config|
                config.channel_secret = ENV['LINE_CHANNEL_SECRET_LIST']
                config.channel_token = ENV['LINE_CHANNEL_TOKEN_LIST']
            }
        end
    end
end

post '/sei_san' do
    body = request.body.read
    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      error 400 do 'Bad Request' end
    end
    events = client.parse_events_from(body)
    events.each do |event|
        case event
            when Line::Bot::Event::Message
                case event.type
                    when Line::Bot::Event::MessageType::Text
                        if event.message['text'].to_i == 0
                            if event.message['text'] == 'キーワード'
                                response_message = "確認\n清算終了\n金額(int)"
                            elsif event.message['text'] == '確認'
                                response_message = ''
                                User.all.each do |user|
                                    response_message << user.name + ':'
                                    response_message << user.paid_total.to_s + '円'
                                    response_message << "\n"
                                end
                                if User.find(1).paid_total > User.find(2).paid_total
                                    total = User.find(1).paid_total - User.find(2).paid_total
                                    response_message << "\n" + User.find(1).name + 'が' + total.to_s + '円多く払っていました。'
                                elsif User.find(1).paid_total < User.find(2).paid_total
                                    total = User.find(2).paid_total - User.find(1).paid_total
                                    response_message << "\n" + User.find(2).name + 'が' + total.to_s + '円多く払っていました。'
                                else 
                                    response_message << "\nピタリ賞！清算はありません！"
                                end
                            elsif event.message['text'] == '清算終了'
                                if User.find(1).paid_total > User.find(2).paid_total
                                    total = User.find(1).paid_total - User.find(2).paid_total
                                    response_message = User.find(1).name + 'が' + total.to_s + '円多く払っていました。'
                                elsif User.find(1).paid_total < User.find(2).paid_total
                                    total = User.find(2).paid_total - User.find(1).paid_total
                                    response_message = User.find(2).name + 'が' + total.to_s + '円多く払っていました。'
                                else 
                                    response_message = 'ピタリ賞！清算はありません！'
                                end
                                User.all.each do |user| 
                                    user.update_column(:paid_total, 0)
                                end
                                response_message << "\n清算額をリセットしました。"
                            else
                                response_message = '払った金額、清算、清算終了のどれかを送ってね！'
                            end
                        else
                            paid = event.message['text'].to_i
                            user_id = event['source']['userId']
                            
                            url = "https://api.line.me/v2/bot/profile/#{user_id}"
                            res = RestClient.get url, { :Authorization => "Bearer #{ENV['LINE_CHANNEL_TOKEN_SEISAN']}" }
                            returned_json = JSON.parse(res.body)
                            user_name =  returned_json["displayName"]
                            
                            user = User.find_by(name: user_name)
                            user.update_column(:paid_total, user.paid_total + (paid / 2))
                            response_message = user_name + 'は現在' + user.paid_total.to_s + '円立て替えています'
                        end
                        message = {
                              type: 'text',
                              text: response_message
                            }
                            
                        client.reply_message(event['replyToken'], message)
                end
        end
    end
end

post '/list' do
    body = request.body.read
    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      error 400 do 'Bad Request' end
    end
    events = client.parse_events_from(body)
    events.each do |event|
        case event
            when Line::Bot::Event::Message
                case event.type
                    when Line::Bot::Event::MessageType::Text
                        message = event.message['text']
                        user_id = event['source']['userId']
                        url = "https://api.line.me/v2/bot/profile/#{user_id}"
                        res = RestClient.get url, { :Authorization => "Bearer #{ENV['LINE_CHANNEL_TOKEN_LIST']}" }
                        returned_json = JSON.parse(res.body)
                        user_name =  returned_json["displayName"]
                        user = User.find_by(name: user_name)
                        unless user.nil?
                            if message.include?('買う')
                                message = message.delete(' ')
                                message = message.delete('　')
                                message = message.slice(2, message.length)
                                new =List.create({
                                    group: '買い物',
                                    content: message
                                })
                                if new.persisted?
                                    response_message = "買い物\n"
                                    List.all.each do |list|
                                        if list.group == '買い物'
                                            response_message << '・' + list.content + "\n"
                                        end
                                    end
                                    response_message << "\nTODO\n"
                                    List.all.each do |list|
                                        if list.group == 'TODO'
                                            response_message << '・' + list.content + "\n"
                                        end
                                    end
                                end
                            elsif message.include?('タスク')
                                message = message.delete(' ')
                                message = message.delete('　')
                                message = message.slice(3, message.length)
                                new = List.create({
                                    group: 'TODO',
                                    content: message
                                })
                                if new.persisted?
                                    response_message = "買い物\n"
                                    List.all.each do |list|
                                        if list.group == '買い物'
                                            response_message << '・' + list.content + "\n"
                                        end
                                    end
                                    response_message << "\nTODO\n"
                                    List.all.each do |list|
                                        if list.group == 'TODO'
                                            response_message << '・' + list.content + "\n"
                                        end
                                    end
                                end
                            elsif message.include?('消す')
                                message = message.delete(' ')
                                message = message.delete('　')
                                message = message.slice(2, message.length)
                                List.find_by(content: message).destroy
                                response_message = "買い物\n"
                                List.all.each do |list|
                                        if list.group == '買い物'
                                            response_message << '・' + list.content + "\n"
                                        end
                                    end
                                    response_message << "\nTODO\n"
                                List.all.each do |list|
                                    if list.group == 'TODO'
                                        response_message << '・' + list.content + "\n"
                                    end
                                end
                            elsif message == "確認"
                                response_message = "買い物\n"
                                List.all.each do |list|
                                        if list.group == '買い物'
                                            response_message << '・' + list.content + "\n"
                                        end
                                    end
                                    response_message << "\nTODO\n"
                                List.all.each do |list|
                                    if list.group == 'TODO'
                                        response_message << '・' + list.content + "\n"
                                    end
                                end
                            elsif message == "リセット"
                                response_message = "リストをリセットします\n"
                                List.all.destroy_all
                                response_message << "買い物\n"
                                List.all.each do |list|
                                    if list.group == '買い物'
                                        response_message << '・' + list.content + "\n"
                                    end
                                end
                                response_message << "\nTODO\n"
                                List.all.each do |list|
                                    if list.group == 'TODO'
                                        response_message << '・' + list.content + "\n"
                                    end
                                end
                            else
                                response_message = "買い物〇〇\n"
                                response_message << "TODO〇〇\n"
                                response_message << "DONE〇〇\n"
                                response_message << "確認 \n"
                                response_message << "消す\n\n"
                                response_message << 'のどれかを送ってね！'
                            end
                        else 
                            response_message = 'not an allowed user'
                        end
                        message = {
                              type: 'text',
                              text: response_message
                            }
                            
                        client.reply_message(event['replyToken'], message)
                end
        end
    end
end
