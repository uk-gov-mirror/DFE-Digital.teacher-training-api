class AuthenticationService
  attr_accessor :encoded_token, :user

  def initialize(logger:)
    @logger = logger
  end

  def execute(encoded_token)
    @encoded_token = encoded_token
    begin
      @user = user_by_sign_in_user_id || user_by_email
      update_user_information
    rescue DuplicateUserError => e
      Raven.capture(e)
    end

    user
  end

private

  attr_reader :logger

  def decoded_token
    @decoded_token ||= Token::DecodeService.call(encoded_token: encoded_token,
      secret: Settings.authentication.secret,
      algorithm: Settings.authentication.algorithm,
      audience: Settings.authentication.audience,
      issuer: Settings.authentication.issuer,
      subject: Settings.authentication.subject)
  end

  def email_from_token
    decoded_token["email"]&.downcase
  end

  def sign_in_user_id_from_token
    decoded_token["sign_in_user_id"]
  end

  def first_name_from_token
    decoded_token["first_name"]
  end

  def last_name_from_token
    decoded_token["last_name"]
  end

  def update_user_information
    return unless user

    update_user_email
    update_user_sign_in_id
    update_user_first_name
    update_user_last_name
  end

  def user_by_email
    if email_from_token.blank?
      logger.debug("No email in token")
      return
    end

    @user_by_email ||= User.find_by("lower(email) = ?", email_from_token)
    if @user_by_email
      logger.info {
        "User found by email address " + {
          user: log_safe_user(@user_by_email),
        }.to_s
      }
    end
    @user_by_email
  end

  def user_by_sign_in_user_id
    if sign_in_user_id_from_token.blank?
      logger.debug("No sign_in_user_id in token")
      return
    end

    user = User.find_by(sign_in_user_id: sign_in_user_id_from_token)
    if user
      logger.info {
        "User found from sign_in_user_id in token " + {
                     sign_in_user_id: sign_in_user_id_from_token,
                     user: log_safe_user(user),
                   }.to_s
      }
    end
    user
  end

  def user_email_does_not_match_token?
    user.email&.downcase != email_from_token
  end

  def user_sign_in_id_does_not_match_token?
    return unless user

    user.sign_in_user_id != sign_in_user_id_from_token
  end

  def email_in_use_by_another_user?
    user_by_email.present?
  end

  def update_user_email
    return unless user_email_does_not_match_token?

    if email_in_use_by_another_user?
      raise DuplicateUserError.new(
        "Duplicate user detected",
        user_id:                       user.id,
        user_sign_in_user_id:          user.sign_in_user_id,
        existing_user_id:              user_by_email.id,
        existing_user_sign_in_user_id: user_by_email.sign_in_user_id,
      )
    else
      logger.debug("Updating user email for " + {
        user: log_safe_user(user),
        new_email_md5: "MD5:#{obfuscate_email(email_from_token)}",
      }.to_s)

      user.update(email: email_from_token)
    end
  end

  def update_user_sign_in_id
    return unless user_sign_in_id_does_not_match_token?

    user.update(sign_in_user_id: sign_in_user_id_from_token)
  end

  def update_user_first_name
    return if first_name_from_token.blank?

    user.update(first_name: first_name_from_token)
  end

  def update_user_last_name
    return if last_name_from_token.blank?

    user.update(last_name: last_name_from_token)
  end

  def log_safe_user(user)
    if @log_safe_user.nil?
      @log_safe_user = user.slice(
        "id",
        "state",
        "first_login_date_utc",
        "last_login_date_utc",
        "sign_in_user_id",
        "welcome_email_date_utc",
        "invite_date_utc",
        "accept_terms_date_utc",
      )
      @log_safe_user["email_md5"] = obfuscate_email(user[:email])
    end
    @log_safe_user
  end

  def obfuscate_email(email)
    Digest::MD5.hexdigest(email)
  end
end
