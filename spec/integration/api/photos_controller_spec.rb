# frozen_sTring_literal: true

require "spec_helper"

describe Api::V1::PhotosController do
  let(:auth) { FactoryGirl.create(:auth_with_read_and_write) }
  let(:auth_read_only) { FactoryGirl.create(:auth_with_read) }
  let!(:access_token) { auth.create_access_token.to_s }
  let!(:access_token_read_only) { auth_read_only.create_access_token.to_s }

  before do
    alice_private_spec = alice.aspects.create(name: "private aspect")
    alice.share_with(eve.person, alice_private_spec)
    @private_photo1 = alice.post(:photo, pending: false, user_file: File.open(photo_fixture_name),
                                to: alice_private_spec.id)
    @alice_public_photo = alice.post(:photo, pending: false, user_file: File.open(photo_fixture_name), public: true)
    @user_photo1 = auth.user.post(:photo, pending: true, user_file: File.open(photo_fixture_name), to: "all")
    @user_photo2 = auth.user.post(:photo, pending: true, user_file: File.open(photo_fixture_name), to: "all")
    message_data = {status_message: {text: "Post with photos"}, public: true, photos: [@user_photo2.id.to_s]}
    @status_message = StatusMessageCreationService.new(auth.user).create(message_data)
    @user_photo2.reload
  end

  describe "#show" do
    context "succeeds" do
      it "with correct GUID user's photo and access token" do
        get(
          api_v1_photo_path(@user_photo1.guid),
          params: {access_token: access_token}
        )
        expect(response.status).to eq(200)
        photo = JSON.parse(response.body)
        expect(photo.has_key?("post")).to be_falsey
        confirm_photo_format(photo, @user_photo1, auth.user)
      end

      it "with correct GUID user's photo used in post and access token" do
        get(
          api_v1_photo_path(@user_photo2.guid),
          params: {access_token: access_token}
        )
        expect(response.status).to eq(200)
        photo = JSON.parse(response.body)
        expect(photo.has_key?("post")).to be_truthy
        confirm_photo_format(photo, @user_photo2, auth.user)
      end

      it "with correct GUID of other user's public photo and access token" do
        get(
          api_v1_photo_path(@alice_public_photo.guid),
          params: {access_token: access_token}
        )
        expect(response.status).to eq(200)
        photo = JSON.parse(response.body)
        confirm_photo_format(photo, @alice_public_photo, alice)
      end
    end

    context "fails" do
      it "with other user's private photo" do
        get(
          api_v1_photo_path(@private_photo1.guid),
          params: {access_token: access_token}
        )
        expect(response.status).to eq(404)
        expect(response.body).to eq(I18n.t("api.endpoint_errors.photos.not_found"))
      end

      it "with invalid GUID" do
        get(
          api_v1_photo_path("999_999_999"),
          params: {access_token: access_token}
        )
        expect(response.status).to eq(404)
        expect(response.body).to eq(I18n.t("api.endpoint_errors.photos.not_found"))
      end

      it "with invalid access token" do
        delete(
          api_v1_photo_path(@user_photo1.guid),
          params: {access_token: "999_999_999"}
        )
        expect(response.status).to eq(401)
      end
    end
  end

  describe "#index" do
    context "succeeds" do
      it "with correct access token" do
        get(
          api_v1_photos_path,
          params: {access_token: access_token}
        )
        expect(response.status).to eq(200)
        photos = response_body_data(response)
        expect(photos.length).to eq(2)
      end
    end

    context "fails" do
      it "with invalid access token" do
        delete(
          api_v1_photos_path,
          params: {access_token: "999_999_999"}
        )
        expect(response.status).to eq(401)
      end
    end
  end

  describe "#create" do
    before do
      @encoded_photo = Rack::Test::UploadedFile.new(
        Rails.root.join("spec", "fixtures", "button.png").to_s,
        "image/png"
      )
    end

    context "succeeds" do
      it "with valid encoded file no arguments" do
        post(
          api_v1_photos_path,
          params: {image: @encoded_photo, access_token: access_token}
        )
        expect(response.status).to eq(200)
        photo = JSON.parse(response.body)
        ref_photo = auth.user.photos.reload.find_by(guid: photo["guid"])
        expect(ref_photo.pending).to be_falsey
        confirm_photo_format(photo, ref_photo, auth.user)
      end

      it "with valid encoded file set as pending" do
        post(
          api_v1_photos_path,
          params: {image: @encoded_photo, pending: false, access_token: access_token}
        )
        expect(response.status).to eq(200)
        photo = JSON.parse(response.body)
        expect(photo.has_key?("post")).to be_falsey
        ref_photo = auth.user.photos.reload.find_by(guid: photo["guid"])
        expect(ref_photo.pending).to be_falsey
        confirm_photo_format(photo, ref_photo, auth.user)

        post(
          api_v1_photos_path,
          params: {image: @encoded_photo, pending: true, access_token: access_token}
        )
        expect(response.status).to eq(200)
        photo = JSON.parse(response.body)
        ref_photo = auth.user.photos.reload.find_by(guid: photo["guid"])
        expect(ref_photo.pending).to be_truthy
      end

      it "with valid encoded file as profile photo" do
        post(
          api_v1_photos_path,
          params: {image: @encoded_photo, set_profile_photo: true, access_token: access_token}
        )
        expect(response.status).to eq(200)
        photo = JSON.parse(response.body)
        expect(auth.user.reload.person.profile.image_url_small).to eq(photo["sizes"]["small"])
      end
    end

    context "fails" do
      it "with no image" do
        post(
          api_v1_photos_path,
          params: {access_token: access_token}
        )
        expect(response.status).to eq(422)
        expect(response.body).to eq(I18n.t("api.endpoint_errors.photos.failed_create"))
      end

      it "with non-image file" do
        text_file = Rack::Test::UploadedFile.new(
          Rails.root.join("README.md").to_s,
          "text/plain"
        )
        post(
          api_v1_photos_path,
          params: {image: text_file, access_token: access_token}
        )
        expect(response.status).to eq(422)
        expect(response.body).to eq(I18n.t("api.endpoint_errors.photos.failed_create"))
      end

      it "with impromperly identified file" do
        text_file = Rack::Test::UploadedFile.new(
          Rails.root.join("README.md").to_s,
          "image/png"
        )
        post(
          api_v1_photos_path,
          params: {image: text_file, access_token: access_token}
        )
        expect(response.status).to eq(422)
        expect(response.body).to eq(I18n.t("api.endpoint_errors.photos.failed_create"))
      end

      it "with invalid access token" do
        post(
          api_v1_photos_path,
          params: {image: @encoded_photo, access_token: "999_999_999"}
        )
        expect(response.status).to eq(401)
      end

      it "with read only access token" do
        post(
          api_v1_photos_path,
          params: {image: @encoded_photo, access_token: access_token_read_only}
        )
        expect(response.status).to eq(403)
      end
    end
  end

  describe "#destroy" do
    context "succeeds" do
      it "with correct GUID and access token" do
        expect(auth.user.photos.find_by(id: @user_photo1.id)).to eq(@user_photo1)
        delete(
          api_v1_photo_path(@user_photo1.guid),
          params: {access_token: access_token}
        )
        expect(response.status).to eq(204)
        expect(auth.user.photos.find_by(id: @user_photo1.id)).to be_nil
      end
    end

    context "fails" do
      it "with other user's photo GUID and access token" do
        delete(
          api_v1_photo_path(@alice_public_photo.guid),
          params: {access_token: access_token}
        )
        expect(response.status).to eq(404)
        expect(response.body).to eq(I18n.t("api.endpoint_errors.photos.not_found"))
      end

      it "with other invalid GUID" do
        delete(
          api_v1_photo_path("999_999_999"),
          params: {access_token: access_token}
        )
        expect(response.status).to eq(404)
        expect(response.body).to eq(I18n.t("api.endpoint_errors.photos.not_found"))
      end

      it "with invalid access token" do
        delete(
          api_v1_photo_path(@user_photo1.guid),
          params: {access_token: "999_999_999"}
        )
        expect(response.status).to eq(401)
      end

      it "with read only access token" do
        delete(
          api_v1_photo_path(@user_photo1.guid),
          params: {access_token: access_token_read_only}
        )
        expect(response.status).to eq(403)
      end
    end
  end

  def response_body_data(response)
    JSON.parse(response.body)["data"]
  end

  # rubocop:disable Metrics/AbcSize
  def confirm_photo_format(photo, ref_photo, ref_user)
    expect(photo["guid"]).to eq(ref_photo.guid)
    if ref_photo.status_message_guid
      expect(photo["post"]).to eq(ref_photo.status_message_guid)
    else
      expect(photo.has_key?("post")).to be_falsey
    end
    expect(photo["dimensions"].has_key?("height")).to be_truthy
    expect(photo["dimensions"].has_key?("width")).to be_truthy
    expect(photo["sizes"]["small"]).to be_truthy
    expect(photo["sizes"]["medium"]).to be_truthy
    expect(photo["sizes"]["large"]).to be_truthy
    confirm_person_format(photo["author"], ref_user)
  end

  def confirm_person_format(post_person, user)
    expect(post_person["guid"]).to eq(user.guid)
    expect(post_person["diaspora_id"]).to eq(user.diaspora_handle)
    expect(post_person["name"]).to eq(user.name)
    expect(post_person["avatar"]).to eq(user.profile.image_url)
  end
  # rubocop:enable Metrics/AbcSize
end
