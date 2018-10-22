class ZCL_APC_WSP_EXT_ZCHAT definition
  public
  inheriting from CL_APC_WSP_EXT_STATELESS_BASE
  final
  create public .

public section.

  methods IF_APC_WSP_EXTENSION~ON_MESSAGE
    redefinition .
  methods IF_APC_WSP_EXTENSION~ON_START
    redefinition .
  methods IF_APC_WSP_EXTENSION~ON_CLOSE
    redefinition .
protected section.
private section.

  types: begin of LTY_CONNECTED_USER,
           id TYPE syuname,
           avatar TYPE i,
         end of LTY_CONNECTED_USER.

  methods SEND_MESSAGE
    importing
      !IM_EXTENSION_ID type AMC_CHANNEL_EXTENSION_ID
      !IM_ROOT_ID type ABAP_TRANS_SRCNAME
      !IM_DATA type ANY .
ENDCLASS.



CLASS ZCL_APC_WSP_EXT_ZCHAT IMPLEMENTATION.


METHOD if_apc_wsp_extension~on_close.

  DATA lt_users TYPE SORTED TABLE OF lty_connected_user WITH UNIQUE KEY id.

  IMPORT users = lt_users FROM DATABASE indx(zc) ID 'ZCHAT'.
  DELETE lt_users WHERE id = sy-uname.
  IF lines( lt_users ) = 0.
    DELETE FROM DATABASE indx(zc) ID 'ZCHAT'.
  ELSE.
    EXPORT users = lt_users TO DATABASE indx(zc) ID 'ZCHAT'.
  ENDIF.

  me->send_message(
      im_extension_id = '/users'
      im_root_id      = 'connectedUsers'
      im_data         = lt_users
  ).

ENDMETHOD.


METHOD if_apc_wsp_extension~on_message.

  DATA: BEGIN OF ls_message,
          text      TYPE string,
          sender    TYPE string,
          timestamp TYPE string,
        END OF ls_message.

  TRY.
      ls_message-text = i_message->get_text( ).
    CATCH cx_apc_error INTO DATA(lx_apc_error).
      MESSAGE lx_apc_error->get_text( ) TYPE 'E'.
  ENDTRY.

  ls_message-sender = sy-uname.
  GET TIME STAMP FIELD DATA(lv_timestamp).
  ls_message-timestamp = |{ lv_timestamp TIMESTAMP = ISO TIMEZONE = sy-zonlo }|.

  me->send_message(
      im_extension_id = '/messages'
      im_root_id      = 'message'
      im_data         = ls_message
  ).

ENDMETHOD.


METHOD if_apc_wsp_extension~on_start.

  DATA lt_users TYPE SORTED TABLE OF lty_connected_user WITH UNIQUE KEY id.

  TRY.
      i_context->get_binding_manager( )->bind_amc_message_consumer(
          i_application_id       = 'ZCHAT'
          i_channel_id           = '/chat'
          i_channel_extension_id = '/users'
      ).
      i_context->get_binding_manager( )->bind_amc_message_consumer(
          i_application_id       = 'ZCHAT'
          i_channel_id           = '/chat'
          i_channel_extension_id = '/messages'
      ).
      DATA(lv_avatar) = i_context->get_initial_request( )->get_form_field( 'avatar' ).
    CATCH cx_apc_error INTO DATA(lx_apc_error).
      MESSAGE lx_apc_error->get_text( ) TYPE 'E'.
  ENDTRY.

  IMPORT users = lt_users FROM DATABASE indx(zc) ID 'ZCHAT'.
  READ TABLE lt_users ASSIGNING FIELD-SYMBOL(<user>) WITH KEY id = sy-uname.
  IF sy-subrc = 0.
    <user>-avatar = lv_avatar.
  ELSE.
    INSERT VALUE lty_connected_user( id = sy-uname avatar = lv_avatar ) INTO lt_users INDEX sy-tabix.
  ENDIF.
  EXPORT users = lt_users TO DATABASE indx(zc) ID 'ZCHAT'.

  me->send_message(
      im_extension_id = '/users'
      im_root_id      = 'connectedUsers'
      im_data         = lt_users
  ).

ENDMETHOD.


METHOD send_message.

  DATA: lo_producer TYPE REF TO if_amc_message_producer_text,
        lv_key      TYPE        string.

  DATA(lt_source) = VALUE abap_trans_srcbind_tab( ( name = im_root_id value = REF #( im_data ) ) ).
  DATA(lo_writer) = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ).
  CALL TRANSFORMATION id SOURCE (lt_source) RESULT XML lo_writer.
  DATA(lv_message) = cl_abap_codepage=>convert_from( lo_writer->get_output( ) ).
  DATA(lv_regex) = '"[\d_\-]*\u+[\u\d_\-]*":'.
  DO count( val = lv_message regex = lv_regex ) TIMES.
    lv_message = replace( val = lv_message regex = lv_regex with = to_lower( match( val = lv_message regex = lv_regex ) ) ).
  ENDDO.

  TRY.
      lo_producer ?= cl_amc_channel_manager=>create_message_producer(
          i_application_id       = 'ZCHAT'
          i_channel_id           = '/chat'
          i_channel_extension_id = im_extension_id
      ).
      lo_producer->send( lv_message ).
    CATCH cx_amc_error INTO DATA(lx_amc_error).
      MESSAGE lx_amc_error->get_text( ) TYPE 'E'.
  ENDTRY.

ENDMETHOD.
ENDCLASS.
