CREATE OR REPLACE FUNCTION notify_seller_new_order()
RETURNS TRIGGER AS $$
DECLARE
  v_seller_name  TEXT;
  v_seller_email TEXT;
  v_seller_phone TEXT;
  v_order_short  TEXT;
BEGIN
  IF NEW.status = 'confirmed' AND OLD.status != 'confirmed' THEN

    SELECT name, email, phone
    INTO v_seller_name, v_seller_email, v_seller_phone
    FROM profiles WHERE id = NEW.seller_id;

    v_order_short := LEFT(NEW.id::TEXT, 8);

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.seller_id, NEW.id, 'email', v_seller_email,
      'new_order_seller',
      jsonb_build_object(
        'seller_name',  v_seller_name,
        'order_short',  v_order_short,
        'order_id',     NEW.id,
        'total_amount', NEW.total_amount,
        'currency',     'XAF',
        'dashboard_url','https://nelmark.cm/dashboard/seller/orders/' || NEW.id
      )
    );

    IF v_seller_phone IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.seller_id, NEW.id, 'whatsapp', v_seller_phone,
        'new_order_seller_whatsapp',
        jsonb_build_object(
          'seller_name',  v_seller_name,
          'order_short',  v_order_short,
          'total_amount', NEW.total_amount,
          'currency',     'XAF'
        )
      );
    END IF;

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_seller_new_order
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION notify_seller_new_order();

CREATE OR REPLACE FUNCTION notify_buyer_order_shipped()
RETURNS TRIGGER AS $$
DECLARE
  v_buyer_name  TEXT;
  v_buyer_email TEXT;
  v_buyer_phone TEXT;
  v_order_short TEXT;
BEGIN
  IF NEW.status = 'shipped' AND OLD.status != 'shipped' THEN

    SELECT name, email, phone
    INTO v_buyer_name, v_buyer_email, v_buyer_phone
    FROM profiles WHERE id = NEW.buyer_id;

    v_order_short := LEFT(NEW.id::TEXT, 8);

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.buyer_id, NEW.id, 'email', v_buyer_email,
      'order_shipped',
      jsonb_build_object(
        'buyer_name',   v_buyer_name,
        'order_short',  v_order_short,
        'order_id',     NEW.id,
        'tracking_url', 'https://nelmark.cm/orders/' || NEW.id
      )
    );

    IF v_buyer_phone IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.buyer_id, NEW.id, 'whatsapp', v_buyer_phone,
        'order_shipped_whatsapp',
        jsonb_build_object(
          'buyer_name',   v_buyer_name,
          'order_short',  v_order_short,
          'tracking_url', 'https://nelmark.cm/orders/' || NEW.id
        )
      );
    END IF;

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_buyer_order_shipped
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION notify_buyer_order_shipped();

CREATE OR REPLACE FUNCTION notify_seller_paid()
RETURNS TRIGGER AS $$
DECLARE
  v_recipient_name  TEXT;
  v_recipient_email TEXT;
  v_recipient_phone TEXT;
BEGIN
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN

    SELECT name, email, phone
    INTO v_recipient_name, v_recipient_email, v_recipient_phone
    FROM profiles WHERE id = NEW.recipient_id;

    IF NEW.recipient_type = 'seller' THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.recipient_id, NEW.order_id, 'email', v_recipient_email,
        'seller_paid',
        jsonb_build_object(
          'seller_name',  v_recipient_name,
          'amount',       NEW.amount,
          'currency',     NEW.currency,
          'order_id',     NEW.order_id,
          'psp_reference',NEW.psp_reference
        )
      );

      IF v_recipient_phone IS NOT NULL THEN
        INSERT INTO notification_queue (
          user_id, order_id, channel, recipient, template, payload
        ) VALUES (
          NEW.recipient_id, NEW.order_id, 'whatsapp', v_recipient_phone,
          'seller_paid_whatsapp',
          jsonb_build_object(
            'seller_name', v_recipient_name,
            'amount',      NEW.amount,
            'currency',    NEW.currency
          )
        );
      END IF;
    END IF;

    IF NEW.recipient_type = 'creator' THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.recipient_id, NEW.order_id, 'email', v_recipient_email,
        'commission_paid',
        jsonb_build_object(
          'creator_name', v_recipient_name,
          'amount',       NEW.amount,
          'currency',     NEW.currency,
          'order_id',     NEW.order_id,
          'psp_reference',NEW.psp_reference
        )
      );

      IF v_recipient_phone IS NOT NULL THEN
        INSERT INTO notification_queue (
          user_id, order_id, channel, recipient, template, payload
        ) VALUES (
          NEW.recipient_id, NEW.order_id, 'whatsapp', v_recipient_phone,
          'commission_paid_whatsapp',
          jsonb_build_object(
            'creator_name', v_recipient_name,
            'amount',       NEW.amount,
            'currency',     NEW.currency
          )
        );
      END IF;
    END IF;

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_paid
  AFTER UPDATE ON payouts
  FOR EACH ROW EXECUTE FUNCTION notify_seller_paid();

CREATE OR REPLACE FUNCTION notify_commission_earned()
RETURNS TRIGGER AS $$
DECLARE
  v_creator_name  TEXT;
  v_creator_email TEXT;
  v_creator_phone TEXT;
  v_product_name  TEXT;
  v_order_short   TEXT;
BEGIN
  SELECT name, email, phone
  INTO v_creator_name, v_creator_email, v_creator_phone
  FROM profiles WHERE id = NEW.creator_id;

  SELECT p.name INTO v_product_name
  FROM order_items oi
  JOIN products p ON p.id = oi.product_id
  WHERE oi.id = NEW.order_item_id;

  v_order_short := LEFT(NEW.order_id::TEXT, 8);

  INSERT INTO notification_queue (
    user_id, order_id, channel, recipient, template, payload
  ) VALUES (
    NEW.creator_id, NEW.order_id, 'email', v_creator_email,
    'commission_earned',
    jsonb_build_object(
      'creator_name',  v_creator_name,
      'amount',        NEW.amount,
      'currency',      'XAF',
      'product_name',  v_product_name,
      'order_short',   v_order_short,
      'dashboard_url', 'https://nelmark.cm/dashboard/creator'
    )
  );

  IF v_creator_phone IS NOT NULL THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.creator_id, NEW.order_id, 'whatsapp', v_creator_phone,
      'commission_earned_whatsapp',
      jsonb_build_object(
        'creator_name', v_creator_name,
        'amount',       NEW.amount,
        'currency',     'XAF',
        'product_name', v_product_name
      )
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_commission_earned
  AFTER INSERT ON commissions
  FOR EACH ROW EXECUTE FUNCTION notify_commission_earned();

CREATE OR REPLACE FUNCTION notify_commission_rejected()
RETURNS TRIGGER AS $$
DECLARE
  v_creator_name  TEXT;
  v_creator_email TEXT;
  v_order_short   TEXT;
BEGIN
  IF NEW.status = 'rejected' AND OLD.status != 'rejected' THEN

    SELECT name, email
    INTO v_creator_name, v_creator_email
    FROM profiles WHERE id = NEW.creator_id;

    v_order_short := LEFT(NEW.order_id::TEXT, 8);

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.creator_id, NEW.order_id, 'email', v_creator_email,
      'commission_rejected',
      jsonb_build_object(
        'creator_name', v_creator_name,
        'amount',       NEW.amount,
        'currency',     'XAF',
        'order_short',  v_order_short,
        'note',         COALESCE(NEW.payment_note, 'Order cancelled')
      )
    );

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_commission_rejected
  AFTER UPDATE ON commissions
  FOR EACH ROW EXECUTE FUNCTION notify_commission_rejected();

CREATE OR REPLACE FUNCTION notify_product_status_change()
RETURNS TRIGGER AS $$
DECLARE
  v_seller_name  TEXT;
  v_seller_email TEXT;
  v_seller_phone TEXT;
BEGIN
  SELECT name, email, phone
  INTO v_seller_name, v_seller_email, v_seller_phone
  FROM profiles WHERE id = NEW.seller_id;

  IF NEW.status = 'published' AND OLD.status != 'published' THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.seller_id, NULL, 'email', v_seller_email,
      'product_approved',
      jsonb_build_object(
        'seller_name',   v_seller_name,
        'product_name',  NEW.name,
        'product_url',   'https://nelmark.cm/products/' || NEW.slug
      )
    );
  END IF;

  IF NEW.status = 'archived'
     AND OLD.status = 'pending_review'
  THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.seller_id, NULL, 'email', v_seller_email,
      'product_rejected',
      jsonb_build_object(
        'seller_name',  v_seller_name,
        'product_name', NEW.name
      )
    );
  END IF;

  IF NEW.stock_count < 5
     AND OLD.stock_count >= 5
     AND NEW.product_type = 'physical'
  THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.seller_id, NULL, 'email', v_seller_email,
      'low_stock_alert',
      jsonb_build_object(
        'seller_name',  v_seller_name,
        'product_name', NEW.name,
        'stock_count',  NEW.stock_count,
        'product_url',  'https://nelmark.cm/dashboard/seller/products/' || NEW.id
      )
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_product_status
  AFTER UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION notify_product_status_change();

CREATE OR REPLACE FUNCTION notify_welcome_and_admin()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_email TEXT;
BEGIN
  INSERT INTO notification_queue (
    user_id, order_id, channel, recipient, template, payload
  ) VALUES (
    NEW.id, NULL, 'email', NEW.email,
    'welcome',
    jsonb_build_object(
      'user_name',   NEW.name,
      'role',        NEW.role,
      'app_url',     'https://nelmark.cm'
    )
  );

  IF NEW.role = 'seller' THEN
    SELECT email INTO v_admin_email
    FROM profiles WHERE role = 'admin' LIMIT 1;

    IF v_admin_email IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.id, NULL, 'email', v_admin_email,
        'new_seller_signup',
        jsonb_build_object(
          'seller_name',  NEW.name,
          'seller_email', NEW.email,
          'admin_url',    'https://nelmark.cm/dashboard/admin/sellers/' || NEW.id
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_welcome
  AFTER INSERT ON profiles
  FOR EACH ROW EXECUTE FUNCTION notify_welcome_and_admin();

CREATE OR REPLACE FUNCTION notify_account_suspended()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_email TEXT;
BEGIN
  IF NEW.is_active = FALSE AND OLD.is_active = TRUE THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.id, NULL, 'email', NEW.email,
      'account_suspended',
      jsonb_build_object(
        'user_name',    NEW.name,
        'support_url',  'https://nelmark.cm/support'
      )
    );
  END IF;

  IF NEW.is_verified = TRUE AND OLD.is_verified = FALSE THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.id, NULL, 'email', NEW.email,
      'seller_verified',
      jsonb_build_object(
        'seller_name', NEW.name,
        'dashboard_url','https://nelmark.cm/dashboard/seller'
      )
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_account_changes
  AFTER UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION notify_account_suspended();

CREATE OR REPLACE FUNCTION notify_admin_product_pending()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_email TEXT;
BEGIN
  IF NEW.status = 'pending_review' AND OLD.status != 'pending_review' THEN

    SELECT email INTO v_admin_email
    FROM profiles WHERE role = 'admin' LIMIT 1;

    IF v_admin_email IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.seller_id, NULL, 'email', v_admin_email,
        'product_pending_review',
        jsonb_build_object(
          'product_name', NEW.name,
          'seller_id',    NEW.seller_id,
          'admin_url',    'https://nelmark.cm/dashboard/admin/products/' || NEW.id
        )
      );
    END IF;

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_admin_product_pending
  AFTER UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION notify_admin_product_pending();

CREATE OR REPLACE FUNCTION notify_admin_suspicious_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_email TEXT;
BEGIN
  IF NEW.is_suspicious = TRUE THEN

    SELECT email INTO v_admin_email
    FROM profiles WHERE role = 'admin' LIMIT 1;

    IF v_admin_email IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.creator_id, NEW.order_id, 'email', v_admin_email,
        'suspicious_commission',
        jsonb_build_object(
          'commission_id', NEW.id,
          'creator_id',    NEW.creator_id,
          'order_id',      NEW.order_id,
          'amount',        NEW.amount,
          'admin_url',     'https://nelmark.cm/dashboard/admin/commissions/' || NEW.id
        )
      );
    END IF;

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_admin_suspicious_commission
  AFTER INSERT ON commissions
  FOR EACH ROW EXECUTE FUNCTION notify_admin_suspicious_commission();

CREATE OR REPLACE FUNCTION notify_admin_new_dispute()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_email TEXT;
BEGIN
  SELECT email INTO v_admin_email
  FROM profiles WHERE role = 'admin' LIMIT 1;

  IF v_admin_email IS NOT NULL THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.buyer_id, NEW.order_id, 'email', v_admin_email,
      'dispute_admin_alert',
      jsonb_build_object(
        'dispute_id',  NEW.id,
        'order_id',    NEW.order_id,
        'reason',      NEW.reason,
        'admin_url',   'https://nelmark.cm/dashboard/admin/disputes/' || NEW.id
      )
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_admin_new_dispute
  AFTER INSERT ON disputes
  FOR EACH ROW EXECUTE FUNCTION notify_admin_new_dispute();