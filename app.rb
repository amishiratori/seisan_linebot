require 'bundler/setup'
Bundler.require
require 'sinatra/reloader' if development?
require './models.rb'
require 'cgi'
require 'json'
require 'line/bot'

def client 
    @client ||= Line::Bot::Client.new { |config|
        config.channel_secret = ENV['LINE_CHANNEL_SECRET']
        config.channel_token = ENV['LINE_CHANNEL_TOKEN']
    }
end

post '/callback' do
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
                        if event.message['text'] == '清算'
                            if User.find(1).paid_total > User.find(2).paid_total
                                total = User.find(1).paid_total - User.find(2).paid_total
                                response_message = User.find(1).name + 'が' + total.to_s + '円多く払っていました。'
                            elsif User.find(1).paid_total < User.find(2).paid_total
                                total = User.find(2).paid_total - User.find(1).paid_total
                                response_message = User.find(2).name + 'が' + total.to_s + '円多く払っていました。'
                            else 
                                response_message = 'ピタリ賞！清算はありません！'
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
                        elsif event.message['text'].to_i == 0
                            response_message = '払った金額、清算、清算終了のどれかを送ってね！'
                        else
                            paid = event.message['text'].to_i
                            room_id = event['source']['roomId']
                            user_id = event['source']['userId']
                            
                            url = "https://api.line.me/v2/bot/room/#{room_id}/member/#{user_id}"
                            res = RestClient.get url, { :Authorization => "Bearer #{ENV['LINE_CHANNEL_TOKEN']}" }
                            returned_json = JSON.parse(res.body)
                            user_name =  returned_json["displayName"]
                            
                            user = User.find_by(name: user_name)
                            user.update_column(:paid_total, user.paid_total + paid / 2)
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