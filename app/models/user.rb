class User
  include Mongoid::Document

  field :email, type: String
  field :name, type: String
  field :active, type: Boolean
  field :level, type: Integer

  embeds_one :credential
  embeds_one :location

  attr_accessible :email, :name, :active, :level

  validates_presence_of :email
  validates :level, inclusion: { in: 1..8, allow_nil: true }

  before_save lambda { active? ? update_location! : location.destroy }

  devise :omniauthable

  acts_as_gmappable process_geocoding: false
  delegate :latitude, to: :location
  delegate :longitude, to: :location

  def self.find_for_google_oauth2(access_token, signed_in_resource=nil)
    user = User.find_or_create_by email: access_token.info.email
    credentials = access_token.credentials
    user.create_credential token: credentials.token, expires_at: Time.at(credentials.expires_at), expires: credentials.expires
    user.credential.update_attribute :refresh_token, credentials.refresh_token unless credentials.refresh_token.nil?
    user
  end

  def update_location!
    client = Google::APIClient.new
    client.authorization.client_id = ENV['GOOGLE_ID']
    client.authorization.client_secret = ENV['GOOGLE_SECRET']
    client.authorization.access_token = credential.token
    client.authorization.refresh_token = credential.refresh_token

    latitude = client.discovered_api('latitude')
    result = client.execute api_method: latitude.current_location.get, parameters: { 'granularity' => 'best' }

    unless result.success? && timestamp > 1.hour.ago
      puts "Update for #{ email } failed"
      location.try :destroy
      return
    end

    data = MultiJson.load(result.body)['data']
    timestamp = Time.at(data['timestampMs'].to_i / 1000)

    unless timestamp > 1.hour.ago
      puts "Location for #{ email } stale"
      location.try :destroy
      return
    end

    create_location timestamp: timestamp, latitude: data['latitude'], longitude: data['longitude'], accuracy: data['accuracy']
  end

end

