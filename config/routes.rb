Rails.application.routes.draw do
  post "/api/resources/:klass/:uuid" => "api/resources#create"
  delete "/api/resources/:klass/:uuid" => "api/resources#destroy"
  put "/api/resources/:klass/:uuid" => "api/resources#update"

  post "/backend/api/resources/:klass/:uuid" => "api/resources#create"
  delete "/backend/api/resources/:klass/:uuid" => "api/resources#destroy"
  put "/backend/api/resources/:klass/:uuid" => "api/resources#update"
end
