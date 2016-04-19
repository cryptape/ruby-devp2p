# -*- encoding : ascii-8bit -*-
require 'test_helper'

class RLPxSessionTest < Minitest::Test
  include DEVp2p

  def test_session
    initiator = RLPxSession.new Crypto::ECCx.new(Crypto.mk_privkey('secret1')), true
    initiator_pubkey = initiator.ecc.raw_pubkey

    responder = RLPxSession.new Crypto::ECCx.new(Crypto.mk_privkey('secret2'))
    responder_pubkey = responder.ecc.raw_pubkey

    auth_msg = initiator.create_auth_message responder_pubkey
    auth_msg_ct = initiator.encrypt_auth_message auth_msg, responder_pubkey

    responder.decode_authentication auth_msg_ct
    auth_ack_msg = responder.create_auth_ack_message
    auth_ack_msg_ct = responder.encrypt_auth_ack_message auth_ack_msg, false, initiator_pubkey

    initiator.decode_auth_ack_message auth_ack_msg_ct

    initiator.setup_cipher
    responder.setup_cipher

    assert_equal ivget(responder, :@ecdhe_shared_secret), ivget(initiator, :@ecdhe_shared_secret)
    assert_equal ivget(responder, :@token), ivget(initiator, :@token)
    assert_equal ivget(responder, :@aes_secret), ivget(initiator, :@aes_secret)
    assert_equal ivget(responder, :@mac_secret), ivget(initiator, :@mac_secret)

    assert_equal ivget(responder, :@egress_mac).digest, ivget(initiator, :@ingress_mac).digest
    assert_equal ivget(responder, :@ingress_mac).digest, ivget(initiator, :@egress_mac).digest

    return initiator, responder
  end

  def test_multiplexing
    initiator, responder = test_session
    imux = Multiplexer.new initiator
    rmux = Multiplexer.new responder

    p1 = 1
    imux.add_protocol p1
    rmux.add_protocol p1

    packet1 = Packet.new p1, 0, "\x00"*100
    imux.add_packet packet1
    msg = imux.pop_all_frames_as_bytes
    packets = rmux.decode(msg)

    assert_equal 1, packets.size
    assert_equal packet1, packets[0]
  end

  def test_many_sessions
    20.times {|i| test_session }
  end

  EIP8Values = {
    key_a: Utils.decode_hex('49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee'),
    key_b: Utils.decode_hex('b71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291'),
    pub_a: Utils.decode_hex('fda1cff674c90c9a197539fe3dfb53086ace64f83ed7c6eabec741f7f381cc803e52ab2cd55d5569bce4347107a310dfd5f88a010cd2ffd1005ca406f1842877'),
    pub_b: Utils.decode_hex('ca634cae0d49acb401d8a4c6b6fe8c55b70d115bf400769cc1400f3258cd31387574077f301b421bc84df7266c44e9e6d569fc56be00812904767bf5ccd1fc7f'),
    eph_key_a: Utils.decode_hex('869d6ecf5211f1cc60418a13b9d870b22959d0c16f02bec714c960dd2298a32d'),
    eph_key_b: Utils.decode_hex('e238eb8e04fee6511ab04c6dd3c89ce097b11f25d584863ac2b6d5b35b1847e4'),
    eph_pub_a: Utils.decode_hex('654d1044b69c577a44e5f01a1209523adb4026e70c62d1c13a067acabc09d2667a49821a0ad4b634554d330a15a58fe61f8a8e0544b310c6de7b0c8da7528a8d'),
    eph_pub_b: Utils.decode_hex('b6d82fa3409da933dbf9cb0140c5dde89f4e64aec88d476af648880f4a10e1e49fe35ef3e69e93dd300b4797765a747c6384a6ecf5db9c2690398607a86181e4'),
    nonce_a: Utils.decode_hex('7e968bba13b6c50e2c4cd7f241cc0d64d1ac25c7f5952df231ac6a2bda8ee5d6'),
    nonce_b: Utils.decode_hex('559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd')
  }

  EIP8Handshakes = [
    { auth: Utils.decode_hex([
       '048ca79ad18e4b0659fab4853fe5bc58eb83992980f4c9cc147d2aa31532efd29a3d3dc6a3d89eaf',
       '913150cfc777ce0ce4af2758bf4810235f6e6ceccfee1acc6b22c005e9e3a49d6448610a58e98744',
       'ba3ac0399e82692d67c1f58849050b3024e21a52c9d3b01d871ff5f210817912773e610443a9ef14',
       '2e91cdba0bd77b5fdf0769b05671fc35f83d83e4d3b0b000c6b2a1b1bba89e0fc51bf4e460df3105',
       'c444f14be226458940d6061c296350937ffd5e3acaceeaaefd3c6f74be8e23e0f45163cc7ebd7622',
       '0f0128410fd05250273156d548a414444ae2f7dea4dfca2d43c057adb701a715bf59f6fb66b2d1d2',
       '0f2c703f851cbf5ac47396d9ca65b6260bd141ac4d53e2de585a73d1750780db4c9ee4cd4d225173',
       'a4592ee77e2bd94d0be3691f3b406f9bba9b591fc63facc016bfa8'].join),
      ack: Utils.decode_hex([
       '049f8abcfa9c0dc65b982e98af921bc0ba6e4243169348a236abe9df5f93aa69d99cadddaa387662',
       'b0ff2c08e9006d5a11a278b1b3331e5aaabf0a32f01281b6f4ede0e09a2d5f585b26513cb794d963',
       '5a57563921c04a9090b4f14ee42be1a5461049af4ea7a7f49bf4c97a352d39c8d02ee4acc416388c',
       '1c66cec761d2bc1c72da6ba143477f049c9d2dde846c252c111b904f630ac98e51609b3b1f58168d',
       'dca6505b7196532e5f85b259a20c45e1979491683fee108e9660edbf38f3add489ae73e3dda2c71b',
       'd1497113d5c755e942d1'].join),
      auth_version: 4,
      ack_version: 4,
      eip8_format: false
    },

    { auth: Utils.decode_hex([
       '01b304ab7578555167be8154d5cc456f567d5ba302662433674222360f08d5f1534499d3678b513b',
       '0fca474f3a514b18e75683032eb63fccb16c156dc6eb2c0b1593f0d84ac74f6e475f1b8d56116b84',
       '9634a8c458705bf83a626ea0384d4d7341aae591fae42ce6bd5c850bfe0b999a694a49bbbaf3ef6c',
       'da61110601d3b4c02ab6c30437257a6e0117792631a4b47c1d52fc0f8f89caadeb7d02770bf999cc',
       '147d2df3b62e1ffb2c9d8c125a3984865356266bca11ce7d3a688663a51d82defaa8aad69da39ab6',
       'd5470e81ec5f2a7a47fb865ff7cca21516f9299a07b1bc63ba56c7a1a892112841ca44b6e0034dee',
       '70c9adabc15d76a54f443593fafdc3b27af8059703f88928e199cb122362a4b35f62386da7caad09',
       'c001edaeb5f8a06d2b26fb6cb93c52a9fca51853b68193916982358fe1e5369e249875bb8d0d0ec3',
       '6f917bc5e1eafd5896d46bd61ff23f1a863a8a8dcd54c7b109b771c8e61ec9c8908c733c0263440e',
       '2aa067241aaa433f0bb053c7b31a838504b148f570c0ad62837129e547678c5190341e4f1693956c',
       '3bf7678318e2d5b5340c9e488eefea198576344afbdf66db5f51204a6961a63ce072c8926c'].join),
      ack: Utils.decode_hex([
       '01ea0451958701280a56482929d3b0757da8f7fbe5286784beead59d95089c217c9b917788989470',
       'b0e330cc6e4fb383c0340ed85fab836ec9fb8a49672712aeabbdfd1e837c1ff4cace34311cd7f4de',
       '05d59279e3524ab26ef753a0095637ac88f2b499b9914b5f64e143eae548a1066e14cd2f4bd7f814',
       'c4652f11b254f8a2d0191e2f5546fae6055694aed14d906df79ad3b407d94692694e259191cde171',
       'ad542fc588fa2b7333313d82a9f887332f1dfc36cea03f831cb9a23fea05b33deb999e85489e645f',
       '6aab1872475d488d7bd6c7c120caf28dbfc5d6833888155ed69d34dbdc39c1f299be1057810f34fb',
       'e754d021bfca14dc989753d61c413d261934e1a9c67ee060a25eefb54e81a4d14baff922180c395d',
       '3f998d70f46f6b58306f969627ae364497e73fc27f6d17ae45a413d322cb8814276be6ddd13b885b',
       '201b943213656cde498fa0e9ddc8e0b8f8a53824fbd82254f3e2c17e8eaea009c38b4aa0a3f306e8',
       '797db43c25d68e86f262e564086f59a2fc60511c42abfb3057c247a8a8fe4fb3ccbadde17514b7ac',
       '8000cdb6a912778426260c47f38919a91f25f4b5ffb455d6aaaf150f7e5529c100ce62d6d92826a7',
       '1778d809bdf60232ae21ce8a437eca8223f45ac37f6487452ce626f549b3b5fdee26afd2072e4bc7',
       '5833c2464c805246155289f4'].join),
      auth_version: 4,
      ack_version: 4,
      eip8_format: true,
    },

    { auth: Utils.decode_hex([
       '01b8044c6c312173685d1edd268aa95e1d495474c6959bcdd10067ba4c9013df9e40ff45f5bfd6f7',
       '2471f93a91b493f8e00abc4b80f682973de715d77ba3a005a242eb859f9a211d93a347fa64b597bf',
       '280a6b88e26299cf263b01b8dfdb712278464fd1c25840b995e84d367d743f66c0e54a586725b7bb',
       'f12acca27170ae3283c1073adda4b6d79f27656993aefccf16e0d0409fe07db2dc398a1b7e8ee93b',
       'cd181485fd332f381d6a050fba4c7641a5112ac1b0b61168d20f01b479e19adf7fdbfa0905f63352',
       'bfc7e23cf3357657455119d879c78d3cf8c8c06375f3f7d4861aa02a122467e069acaf513025ff19',
       '6641f6d2810ce493f51bee9c966b15c5043505350392b57645385a18c78f14669cc4d960446c1757',
       '1b7c5d725021babbcd786957f3d17089c084907bda22c2b2675b4378b114c601d858802a55345a15',
       '116bc61da4193996187ed70d16730e9ae6b3bb8787ebcaea1871d850997ddc08b4f4ea668fbf3740',
       '7ac044b55be0908ecb94d4ed172ece66fd31bfdadf2b97a8bc690163ee11f5b575a4b44e36e2bfb2',
       'f0fce91676fd64c7773bac6a003f481fddd0bae0a1f31aa27504e2a533af4cef3b623f4791b2cca6',
       'd490'].join),
      ack: Utils.decode_hex([
       '01f004076e58aae772bb101ab1a8e64e01ee96e64857ce82b1113817c6cdd52c09d26f7b90981cd7',
       'ae835aeac72e1573b8a0225dd56d157a010846d888dac7464baf53f2ad4e3d584531fa203658fab0',
       '3a06c9fd5e35737e417bc28c1cbf5e5dfc666de7090f69c3b29754725f84f75382891c561040ea1d',
       'dc0d8f381ed1b9d0d4ad2a0ec021421d847820d6fa0ba66eaf58175f1b235e851c7e2124069fbc20',
       '2888ddb3ac4d56bcbd1b9b7eab59e78f2e2d400905050f4a92dec1c4bdf797b3fc9b2f8e84a482f3',
       'd800386186712dae00d5c386ec9387a5e9c9a1aca5a573ca91082c7d68421f388e79127a5177d4f8',
       '590237364fd348c9611fa39f78dcdceee3f390f07991b7b47e1daa3ebcb6ccc9607811cb17ce51f1',
       'c8c2c5098dbdd28fca547b3f58c01a424ac05f869f49c6a34672ea2cbbc558428aa1fe48bbfd6115',
       '8b1b735a65d99f21e70dbc020bfdface9f724a0d1fb5895db971cc81aa7608baa0920abb0a565c9c',
       '436e2fd13323428296c86385f2384e408a31e104670df0791d93e743a3a5194ee6b076fb6323ca59',
       '3011b7348c16cf58f66b9633906ba54a2ee803187344b394f75dd2e663a57b956cb830dd7a908d4f',
       '39a2336a61ef9fda549180d4ccde21514d117b6c6fd07a9102b5efe710a32af4eeacae2cb3b1dec0',
       '35b9593b48b9d3ca4c13d245d5f04169b0b1'].join),
      auth_version: 56,
      ack_version: 57,
      eip8_format: true,
    }
  ]

  def test_eip8_handshake_messages
    initiator = RLPxSession.new Crypto::ECCx.new(EIP8Values[:key_a]), true
    responder = RLPxSession.new Crypto::ECCx.new(EIP8Values[:key_b])

    EIP8Handshakes.each do |handshake|
      ack_rest = initiator.decode_auth_ack_message handshake[:ack]
      assert_equal EIP8Values[:eph_pub_b], ivget(initiator, :@remote_ephemeral_pubkey)
      assert_equal EIP8Values[:nonce_b], ivget(initiator, :@responder_nonce)
      assert_equal handshake[:eip8_format], ivget(initiator, :@got_eip8_ack)
      assert_equal handshake[:ack_version], ivget(initiator, :@remote_version)
      assert_equal '', ack_rest

      auth_rest = responder.decode_authentication handshake[:auth]
      assert_equal EIP8Values[:eph_pub_a], ivget(responder, :@remote_ephemeral_pubkey)
      assert_equal EIP8Values[:nonce_a], ivget(responder, :@initiator_nonce)
      assert_equal EIP8Values[:pub_a], ivget(responder, :@remote_pubkey)
      assert_equal handshake[:eip8_format], ivget(responder, :@got_eip8_auth)
      assert_equal '', auth_rest
    end
  end

  def test_eip8_key_derivation
    responder = RLPxSession.new Crypto::ECCx.new(EIP8Values[:key_b]), false, EIP8Values[:eph_key_b]
    responder.decode_authentication EIP8Handshakes[1][:auth]
    ack = responder.create_auth_ack_message nil, EIP8Values[:nonce_b]
    responder.encrypt_auth_ack_message ack

    responder.setup_cipher
    want_aes_secret = Utils.decode_hex('80e8632c05fed6fc2a13b0f8d31a3cf645366239170ea067065aba8e28bac487')
    want_mac_secret = Utils.decode_hex('2ea74ec5dae199227dff1af715362700e989d889d7a493cb0639691efb8e5f98')
    assert_equal want_aes_secret, ivget(responder, :@aes_secret)
    assert_equal want_mac_secret, ivget(responder, :@mac_secret)

    mac_digest = responder.ingress_mac('foo')
    want_mac_digest = Utils.decode_hex '0c7ec6340062cc46f5e9f1e3cf86f8c8c403c5a0964f5df0ebd34a75ddc86db5'
    assert_equal want_mac_digest, mac_digest
  end

  def test_auth_ack_is_eip8_for_eip8_auth
    responder = RLPxSession.new Crypto::ECCx.new(EIP8Values[:key_b])
    responder.decode_authentication EIP8Handshakes[1][:auth]
    assert ivget(responder, :@got_eip8_auth)

    ack = responder.create_auth_ack_message nil, nil, 55
    ack_ct = responder.encrypt_auth_ack_message ack

    initiator = RLPxSession.new Crypto::ECCx.new(EIP8Values[:key_a]), true
    initiator.decode_auth_ack_message ack_ct
    assert ivget(initiator, :@got_eip8_ack)
    assert_equal 55, initiator.remote_version
  end

  def test_macs
    initiator, responder = test_session

    assert_equal responder.egress_mac(''), initiator.ingress_mac('')
    assert_equal responder.ingress_mac(''), initiator.egress_mac('')

    5.times do |i|
      msg = 'test'
      id = initiator.egress_mac(msg)
      rd = responder.ingress_mac(msg)
      assert_equal id, rd
    end
  end

  def test_mac_enc
    initiator, responder = test_session

    msg = 'a'*16
    assert_equal responder.mac_enc(msg), initiator.mac_enc(msg)
  end

  def test_aes_enc
    initiator, responder = test_session

    msg = 'test'
    c = initiator.aes_enc(msg)
    assert_equal msg.size, c.size

    d = responder.aes_dec(c)
    assert_equal msg, d
  end

  def test_encryption
    initiator, responder = test_session

    5.times do |i|
      msg_frame = Utils.keccak256("#{i}f") * i + 'notpadded'
      msg_frame_padded = Utils.rzpad16 msg_frame

      msg_header = Frame.encode_body_size(msg_frame.size) + Utils.keccak256(i.to_s)[0,16-3]
      msg_ct = initiator.encrypt msg_header, msg_frame_padded

      r = responder.decrypt msg_ct
      assert_equal msg_header, r[:header]
      assert_equal msg_frame, r[:frame]
    end

    5.times do |i|
      msg_frame = Utils.keccak256 "#{i}f"
      msg_header = Frame.encode_body_size(msg_frame.size) + Utils.keccak256(i.to_s)[0,16-3]
      msg_ct = responder.encrypt(msg_header, msg_frame)

      r = initiator.decrypt msg_ct
      assert_equal msg_header, r[:header]
      assert_equal msg_frame, r[:frame]
    end
  end

  def test_body_length
    initiator, responder = test_session

    msg_frame = Utils.keccak256('test') + 'notpadded'
    msg_frame_padded = Utils.rzpad16 msg_frame
    msg_header = Frame.encode_body_size(msg_frame.size) + Utils.keccak256('x')[0,16-3]
    msg_ct = initiator.encrypt(msg_header, msg_frame_padded)

    r = responder.decrypt msg_ct
    assert_equal msg_header, r[:header]
    assert_equal msg_frame, r[:frame]

    # test excess data
    msg_ct2 = initiator.encrypt msg_header, msg_frame_padded
    r = responder.decrypt "#{msg_ct2}excess data"
    assert_equal msg_header, r[:header]
    assert_equal msg_frame, r[:frame]
    assert_equal msg_ct.size, r[:bytes_read]

    # test data underflow
    data = initiator.encrypt msg_header, msg_frame_padded
    header = responder.decrypt_header data[0,32]
    body_size = Frame.decode_body_size(header)
    assert_raises(FormatError) { responder.decrypt_body data[32...-1], body_size }
  end

end
