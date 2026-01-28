package com.marianhello.bgloc.data.sqlite;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.util.Log;

import org.json.JSONObject;
import org.json.JSONException;

import com.marianhello.bgloc.Config;
import com.marianhello.bgloc.data.ConfigurationDAO;
import com.marianhello.bgloc.data.LocationTemplateFactory;
import com.marianhello.bgloc.data.sqlite.SQLiteConfigurationContract.ConfigurationEntry;

public class SQLiteConfigurationDAO implements ConfigurationDAO {
  private static final String TAG = SQLiteConfigurationDAO.class.getName();

    private SQLiteDatabase db;

  public SQLiteConfigurationDAO(Context context) {
    SQLiteOpenHelper helper = SQLiteOpenHelper.getHelper(context);
    this.db = helper.getWritableDatabase();
  }

  public SQLiteConfigurationDAO(SQLiteDatabase db) {
    this.db = db;
  }

  public Config retrieveConfiguration() throws JSONException {
    Cursor cursor = null;

    String[] columns = {
      ConfigurationEntry._ID,
      ConfigurationEntry.COLUMN_NAME_RADIUS,
      ConfigurationEntry.COLUMN_NAME_DISTANCE_FILTER,
      ConfigurationEntry.COLUMN_NAME_DESIRED_ACCURACY,
      ConfigurationEntry.COLUMN_NAME_DEBUG,
      ConfigurationEntry.COLUMN_NAME_NOTIF_TITLE,
      ConfigurationEntry.COLUMN_NAME_NOTIF_TEXT,
      ConfigurationEntry.COLUMN_NAME_NOTIF_ICON_LARGE,
      ConfigurationEntry.COLUMN_NAME_NOTIF_ICON_SMALL,
      ConfigurationEntry.COLUMN_NAME_NOTIF_COLOR,
      ConfigurationEntry.COLUMN_NAME_STOP_TERMINATE,
      ConfigurationEntry.COLUMN_NAME_STOP_ON_STILL,
      ConfigurationEntry.COLUMN_NAME_START_BOOT,
      ConfigurationEntry.COLUMN_NAME_START_FOREGROUND,
      ConfigurationEntry.COLUMN_NAME_NOTIFICATIONS_ENABLED,
      ConfigurationEntry.COLUMN_NAME_LOCATION_PROVIDER,
      ConfigurationEntry.COLUMN_NAME_INTERVAL,
      ConfigurationEntry.COLUMN_NAME_FASTEST_INTERVAL,
      ConfigurationEntry.COLUMN_NAME_ACTIVITIES_INTERVAL,
      ConfigurationEntry.COLUMN_NAME_REMINDER_INTERVAL_MINUTES,
      ConfigurationEntry.COLUMN_NAME_REMINDER_SNOOZE_MINUTES,
      ConfigurationEntry.COLUMN_NAME_REMINDER_TITLE,
      ConfigurationEntry.COLUMN_NAME_REMINDER_TEXT,
      ConfigurationEntry.COLUMN_NAME_REMINDER_STOP_LABEL,
      ConfigurationEntry.COLUMN_NAME_REMINDER_SNOOZE_LABEL,
      ConfigurationEntry.COLUMN_NAME_REMINDER_MUTE_LABEL,
      ConfigurationEntry.COLUMN_NAME_URL,
      ConfigurationEntry.COLUMN_NAME_SYNC_URL,
      ConfigurationEntry.COLUMN_NAME_SYNC_THRESHOLD,
      ConfigurationEntry.COLUMN_NAME_HEADERS,
      ConfigurationEntry.COLUMN_NAME_USE_WEBVIEW_COOKIE_STORE,
      ConfigurationEntry.COLUMN_NAME_MAX_LOCATIONS,
      ConfigurationEntry.COLUMN_NAME_TEMPLATE
    };

    String whereClause = null;
    String[] whereArgs = null;
    String groupBy = null;
    String having = null;
    String orderBy = null;

    Config config = null;
    try {
      cursor = db.query(
          ConfigurationEntry.TABLE_NAME,  // The table to query
          columns,                   // The columns to return
          whereClause,               // The columns for the WHERE clause
          whereArgs,                 // The values for the WHERE clause
          groupBy,                   // don't group the rows
          having,                    // don't filter by row groups
          orderBy                    // The sort order
      );
      if (cursor.moveToFirst()) {
        config = hydrate(cursor);
      }
    } finally {
      if (cursor != null) {
        cursor.close();
      }
    }
    return config;
  }

  public boolean persistConfiguration(Config config) throws NullPointerException {
    long rowId = db.replace(ConfigurationEntry.TABLE_NAME, ConfigurationEntry.COLUMN_NAME_NULLABLE, getContentValues(config));
    Log.d(TAG, "Configuration persisted with rowId = " + rowId);
    if (rowId > -1) {
      return true;
    } else {
      return false;
    }
  }

  private Config hydrate(Cursor c) throws JSONException {
    Config config = Config.getDefault();
    config.setStationaryRadius(c.getFloat(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_RADIUS)));
    config.setDistanceFilter(c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_DISTANCE_FILTER)));
    config.setDesiredAccuracy(c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_DESIRED_ACCURACY)));
    config.setDebugging( (c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_DEBUG)) == 1) ? true : false );
    config.setNotificationTitle(c.getString(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_NOTIF_TITLE)));
    config.setNotificationText(c.getString(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_NOTIF_TEXT)));
    config.setSmallNotificationIcon(c.getString(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_NOTIF_ICON_SMALL)));
    config.setLargeNotificationIcon(c.getString(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_NOTIF_ICON_LARGE)));
    config.setNotificationIconColor(c.getString(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_NOTIF_COLOR)));
    config.setStopOnTerminate( (c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_STOP_TERMINATE)) == 1) ? true : false );
    config.setStopOnStillActivity( (c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_STOP_ON_STILL)) == 1) ? true : false );
    config.setStartOnBoot( (c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_START_BOOT)) == 1) ? true : false );
    config.setStartForeground( (c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_START_FOREGROUND)) == 1) ? true : false );
    config.setNotificationsEnabled( (c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_NOTIFICATIONS_ENABLED)) == 1) ? true : false );
    config.setLocationProvider(c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_LOCATION_PROVIDER)));
    config.setInterval(c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_INTERVAL)));
    config.setFastestInterval(c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_FASTEST_INTERVAL)));
    config.setActivitiesInterval(c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_ACTIVITIES_INTERVAL)));
    int reminderIntervalIdx = c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_REMINDER_INTERVAL_MINUTES);
    if (reminderIntervalIdx > -1 && !c.isNull(reminderIntervalIdx)) {
      config.setStillTrackingReminderIntervalMinutes(c.getInt(reminderIntervalIdx));
    }
    int reminderSnoozeIdx = c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_REMINDER_SNOOZE_MINUTES);
    if (reminderSnoozeIdx > -1 && !c.isNull(reminderSnoozeIdx)) {
      config.setStillTrackingReminderSnoozeIntervalMinutes(c.getInt(reminderSnoozeIdx));
    }
    int reminderTitleIdx = c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_REMINDER_TITLE);
    if (reminderTitleIdx > -1 && !c.isNull(reminderTitleIdx)) {
      config.setStillTrackingReminderTitle(c.getString(reminderTitleIdx));
    }
    int reminderTextIdx = c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_REMINDER_TEXT);
    if (reminderTextIdx > -1 && !c.isNull(reminderTextIdx)) {
      config.setStillTrackingReminderText(c.getString(reminderTextIdx));
    }
    int reminderStopLabelIdx = c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_REMINDER_STOP_LABEL);
    if (reminderStopLabelIdx > -1 && !c.isNull(reminderStopLabelIdx)) {
      config.setStillTrackingReminderStopLabel(c.getString(reminderStopLabelIdx));
    }
    int reminderSnoozeLabelIdx = c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_REMINDER_SNOOZE_LABEL);
    if (reminderSnoozeLabelIdx > -1 && !c.isNull(reminderSnoozeLabelIdx)) {
      config.setStillTrackingReminderSnoozeLabel(c.getString(reminderSnoozeLabelIdx));
    }
    int reminderMuteLabelIdx = c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_REMINDER_MUTE_LABEL);
    if (reminderMuteLabelIdx > -1 && !c.isNull(reminderMuteLabelIdx)) {
      config.setStillTrackingReminderMuteLabel(c.getString(reminderMuteLabelIdx));
    }
    config.setUrl(c.getString(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_URL)));
    config.setSyncUrl(c.getString(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_SYNC_URL)));
    config.setSyncThreshold(c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_SYNC_THRESHOLD)));
    config.setHttpHeaders(new JSONObject(c.getString(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_HEADERS))));
    config.setUseWebViewCookieStore((c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_USE_WEBVIEW_COOKIE_STORE)) == 1) ? true : false);
    config.setMaxLocations(c.getInt(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_MAX_LOCATIONS)));
    config.setTemplate(LocationTemplateFactory.fromJSONString(c.getString(c.getColumnIndex(ConfigurationEntry.COLUMN_NAME_TEMPLATE))));

    return config;
  }

  private ContentValues getContentValues(Config config) throws NullPointerException {
    ContentValues values = new ContentValues();
    values.put(ConfigurationEntry._ID, 1);
    values.put(ConfigurationEntry.COLUMN_NAME_RADIUS, config.getStationaryRadius());
    values.put(ConfigurationEntry.COLUMN_NAME_DISTANCE_FILTER, config.getDistanceFilter());
    values.put(ConfigurationEntry.COLUMN_NAME_DESIRED_ACCURACY, config.getDesiredAccuracy());
    values.put(ConfigurationEntry.COLUMN_NAME_DEBUG, (config.isDebugging() == true) ? 1 : 0);
    values.put(ConfigurationEntry.COLUMN_NAME_NOTIF_TITLE, config.getNotificationTitle());
    values.put(ConfigurationEntry.COLUMN_NAME_NOTIF_TEXT, config.getNotificationText());
    values.put(ConfigurationEntry.COLUMN_NAME_NOTIF_ICON_SMALL, config.getSmallNotificationIcon());
    values.put(ConfigurationEntry.COLUMN_NAME_NOTIF_ICON_LARGE, config.getLargeNotificationIcon());
    values.put(ConfigurationEntry.COLUMN_NAME_NOTIF_COLOR, config.getNotificationIconColor());
    values.put(ConfigurationEntry.COLUMN_NAME_STOP_TERMINATE, (config.getStopOnTerminate() == true) ? 1 : 0);
    values.put(ConfigurationEntry.COLUMN_NAME_STOP_ON_STILL, (config.getStopOnStillActivity() == true) ? 1 : 0);
    values.put(ConfigurationEntry.COLUMN_NAME_START_BOOT, (config.getStartOnBoot() == true) ? 1 : 0);
    values.put(ConfigurationEntry.COLUMN_NAME_START_FOREGROUND, (config.getStartForeground() == true) ? 1 : 0);
    values.put(ConfigurationEntry.COLUMN_NAME_NOTIFICATIONS_ENABLED, (config.getNotificationsEnabled() == true) ? 1 : 0);
    values.put(ConfigurationEntry.COLUMN_NAME_LOCATION_PROVIDER, config.getLocationProvider());
    values.put(ConfigurationEntry.COLUMN_NAME_INTERVAL, config.getInterval());
    values.put(ConfigurationEntry.COLUMN_NAME_FASTEST_INTERVAL, config.getFastestInterval());
    values.put(ConfigurationEntry.COLUMN_NAME_ACTIVITIES_INTERVAL, config.getActivitiesInterval());
    values.put(ConfigurationEntry.COLUMN_NAME_REMINDER_INTERVAL_MINUTES, config.hasStillTrackingReminderIntervalMinutes() ? config.getStillTrackingReminderIntervalMinutes() : null);
    values.put(ConfigurationEntry.COLUMN_NAME_REMINDER_SNOOZE_MINUTES, config.hasStillTrackingReminderSnoozeIntervalMinutes() ? config.getStillTrackingReminderSnoozeIntervalMinutes() : null);
    values.put(ConfigurationEntry.COLUMN_NAME_REMINDER_TITLE, config.hasStillTrackingReminderTitle() && config.getStillTrackingReminderTitle() != Config.NullString ? config.getStillTrackingReminderTitle() : null);
    values.put(ConfigurationEntry.COLUMN_NAME_REMINDER_TEXT, config.hasStillTrackingReminderText() && config.getStillTrackingReminderText() != Config.NullString ? config.getStillTrackingReminderText() : null);
    values.put(ConfigurationEntry.COLUMN_NAME_REMINDER_STOP_LABEL, config.hasStillTrackingReminderStopLabel() && config.getStillTrackingReminderStopLabel() != Config.NullString ? config.getStillTrackingReminderStopLabel() : null);
    values.put(ConfigurationEntry.COLUMN_NAME_REMINDER_SNOOZE_LABEL, config.hasStillTrackingReminderSnoozeLabel() && config.getStillTrackingReminderSnoozeLabel() != Config.NullString ? config.getStillTrackingReminderSnoozeLabel() : null);
    values.put(ConfigurationEntry.COLUMN_NAME_REMINDER_MUTE_LABEL, config.hasStillTrackingReminderMuteLabel() && config.getStillTrackingReminderMuteLabel() != Config.NullString ? config.getStillTrackingReminderMuteLabel() : null);
    values.put(ConfigurationEntry.COLUMN_NAME_URL, config.getUrl());
    values.put(ConfigurationEntry.COLUMN_NAME_SYNC_URL, config.getSyncUrl());
    values.put(ConfigurationEntry.COLUMN_NAME_SYNC_THRESHOLD, config.getSyncThreshold());
    values.put(ConfigurationEntry.COLUMN_NAME_HEADERS, new JSONObject(config.getHttpHeaders()).toString());
    values.put(ConfigurationEntry.COLUMN_NAME_USE_WEBVIEW_COOKIE_STORE, (config.getUseWebViewCookieStore() == true) ? 1 : 0);
    values.put(ConfigurationEntry.COLUMN_NAME_MAX_LOCATIONS, config.getMaxLocations());
    values.put(ConfigurationEntry.COLUMN_NAME_TEMPLATE, config.hasTemplate() ? config.getTemplate().toString() : null);

    return values;
  }
}
