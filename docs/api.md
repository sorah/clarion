# Clarion API

- Registration flow:
  - _app_ redirects or submits `<form>` post to `/register`
  - _Clarion_ does key registration work with user
  - _Clarion_ redirects user back to a specified _callback_ 
  - _app_ stores the key information
- Authentication flow:
  - _app_ requests _Clarion_ for authentication (POST `/api/authn`)
  - _app_ navigates user to authentication URL presented by _Clarion_
  - _Clarion_ does U2F authentication work
  - _app_ polls `/api/authn/:id` for authentication result

Pro Tips: _app_ could be anything (browser, CLI, etc) and _app_ for registration, and _app_ for authentication may be different.

## POST `/api/authn` (Request authentication)

### Request

application/json

``` json
{
  "name": "alice",
  "comment": "SSH logging in",
  "keys": [
    {
      "name": "my security key",
      "handle": "KEYHANDLE",
      "public_key": "PUBLICKEY",
      "counter": 42
    }
  ]
}
```

- `name` (optional): used for consenting user
- `comment` (optional): used for consenting user
- keys: array of _key_ objects, which is retrievable by `/register` API
  - `name` (optional)
  - `handle` (required)
  - `public_key` (required)
  - `counter` (optional)


### Response

Same with `/api/authn/:id`

## GET `/api/authn/:id` (Check authentication result)

### Request

- `:id` authn ID

### Response

``` json
{
  "authn": {
    "id": "bwsyJySllmJpFeIV4VuSPg9xO9Bdky905i48K1kA02Yd8l6C7-l4GlvPA8icYPLPxG4xkp9ePUp_3Onsemc",
    "status": "open",
    "html_url": "https://example.org/authn/bwsyJySllmJpFeIV4VuSPg9xO9Bdky905i48K1kA02Yd8l6C7-l4GlvPA8icYPLPxG4xkp9ePUp_3Onsemc",
    "url": "https://example.org/api/authn/bwsyJySllmJpFeIV4VuSPg9xO9Bdky905i48K1kA02Yd8l6C7-l4GlvPA8icYPLPxG4xkp9ePUp_3Onsemc",
    "created_at": "2017-12-08T01:14:41+09:00",
    "expires_at": "2017-12-08T01:16:41+09:00",
    "verified_at": "2017-12-08T01:15:41+09:00",
    "verified_key": {
      "name": "my security key",
      "handle": "KEYHANDLE",
      "public_key": "PUBLICKEY",
      "counter": 43
    }
  }
}
```

- `id`: authn ID
- `status`: One of = `open`, `verified`, `expired`, or `cancelled`
- `html_url`: URL of authentication page for user
- `url`: API URL to retrieve the latest authn status (`/api/authn/:id`)
- `created_at`: Creation time of authn, format is ISO8601
- `expires_at`: Expiration time of authn, format is ISO8601
- (only available when `status == "verified"`)
  - `verified_at` : verification time of authn, format is ISO8601.
  - `verified_key` : a _key_ object, user presented.

## GET/POST `/register` (Security Key Registration page)

Navigate user to this page for key registration. Clarion redirects back to _callback_ with registered key information.

### Request

form encoded body on POST, or query string on GET

```
name=NAME&comment=COMMENT&state=STATE&callback=CALLBACK&public_key=PUBKEY
```

- `NAME` (optional): Used for consenting user
- `COMMENT` (optional): Used for consenting user
- `STATE` (optional): if given, the same string will be returned in a callback
- `CALLBACK` (required): Callback URL
  - may start with `js:`: When `js:$ORIGIN` (where `$ORIGIN` is a page origin) is specified, `/register` page will return a result using [window.opener.postMessage()](https://developer.mozilla.org/en-US/docs/Web/API/Window/postMessage).
  - Returned message is a JavaScript object contains a property `clarion_key`. It is a JavaScript object in the same format of POST callback.
- `PUBKEY` (required): RSA public key, in a Base64 encoded DER string.

### Response

HTML for user

## POST (callback) (Security Key Registration callback)

callback (by redirection) that notifies key registration, with the registered key information to the _app_

### Request

form encoded

```
state=STATE&data=DATA
```

- `DATA` is a JSON string `{"data": "ENCRYPT_DATA_BASE64", "key": "ENCRYPTED_SHARED_KEY_BASE64"}`.
  - `ENCRYPTED_SHARED_KEY_BASE64` contains base64 encoded binary, which is a RSA encrypted JSON string using the given RSA public key to `/register`. RSA padding mode is `PKCS1_OAEP_PADDING`.
    - it decrypts like as `{"iv": "IV_BASE64", "tag": "TAG_BASE64", "key": "KEY_BASE64"}`.
    - `IV_BASE64` is a base64 encoded IV.
    - `TAG_BASE64` is a AES-GCM auth tag.
    - `KEY_BASE64` is a base64 encoded shared key used for AES-256-GCM.
  - `ENCRYPTED_DATA_BASE64` is a base64 encoded binary, which is a AES-256-GCM encrypted JSON string. Use `IV_BASE64`, `TAG_BASE64`, `KEY_BASE64` to decrypt.

`ENCRYPTED_DATA_BASE64` decrypted as like the following JSON string:

``` json
{
  "name": "KEYNAME",
  "handle": "KEYHANDLE",
  "public_key": "PUBLICKEY"
}
```

