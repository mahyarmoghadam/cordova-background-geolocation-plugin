package com.marianhello.bgloc;

import android.os.Build;
import android.webkit.CookieManager;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.Iterator;

import java.net.URL;
import java.net.HttpURLConnection;
import java.io.OutputStreamWriter;

public class HttpPostService {
    public static final int BUFFER_SIZE = 1024;

    private String mUrl;
    private HttpURLConnection mHttpURLConnection;

    public interface UploadingProgressListener {
        void onProgress(int progress);
    }

    public HttpPostService(String url) {
        mUrl = url;
    }

    public HttpPostService(final HttpURLConnection httpURLConnection) {
        mHttpURLConnection = httpURLConnection;
    }

    private HttpURLConnection openConnection() throws IOException {
        if (mHttpURLConnection == null) {
            mHttpURLConnection = (HttpURLConnection) new URL(mUrl).openConnection();
        }
        return mHttpURLConnection;
    }

    private static boolean hasHeaderIgnoreCase(Map headers, String headerName) {
        if (headers == null || headerName == null) {
            return false;
        }

        Iterator<Map.Entry<String, String>> it = headers.entrySet().iterator();
        while (it.hasNext()) {
            Map.Entry<String, String> pair = it.next();
            if (pair.getKey() != null && headerName.equalsIgnoreCase(pair.getKey())) {
                return true;
            }
        }

        return false;
    }

    private static void applyWebViewCookiesIfNeeded(HttpURLConnection conn, String url, Map headers, boolean useWebViewCookieStore) {
        if (!useWebViewCookieStore || conn == null || url == null) {
            return;
        }

        // Don't override explicit Cookie header from user-provided httpHeaders
        if (hasHeaderIgnoreCase(headers, "Cookie")) {
            return;
        }

        try {
            CookieManager cookieManager = CookieManager.getInstance();
            String cookieHeader = cookieManager.getCookie(url);
            if (cookieHeader != null && !cookieHeader.isEmpty()) {
                conn.setRequestProperty("Cookie", cookieHeader);
            }
        } catch (Throwable ignored) {
            // Best-effort only: CookieManager may not be available / initialized in some environments
        }
    }

    private static void persistResponseCookiesIfNeeded(HttpURLConnection conn, String url, boolean useWebViewCookieStore) {
        if (!useWebViewCookieStore || conn == null || url == null) {
            return;
        }

        try {
            CookieManager cookieManager = CookieManager.getInstance();
            Map<String, java.util.List<String>> headerFields = conn.getHeaderFields();
            if (headerFields != null) {
                for (Map.Entry<String, java.util.List<String>> entry : headerFields.entrySet()) {
                    String headerKey = entry.getKey();
                    if (headerKey == null) {
                        continue;
                    }
                    if (!"Set-Cookie".equalsIgnoreCase(headerKey) && !"Set-Cookie2".equalsIgnoreCase(headerKey)) {
                        continue;
                    }
                    java.util.List<String> values = entry.getValue();
                    if (values == null) {
                        continue;
                    }
                    for (String setCookieValue : values) {
                        if (setCookieValue != null && !setCookieValue.isEmpty()) {
                            cookieManager.setCookie(url, setCookieValue);
                        }
                    }
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                cookieManager.flush();
            }
        } catch (Throwable ignored) {
            // Best-effort only
        }
    }

    public int postJSON(JSONObject json, Map headers) throws IOException {
        String jsonString = "null";
        if (json != null) {
            jsonString = json.toString();
        }

        return postJSONString(jsonString, headers);
    }

    public int postJSON(JSONArray json, Map headers) throws IOException {
        String jsonString = "null";
        if (json != null) {
            jsonString = json.toString();
        }

        return postJSONString(jsonString, headers);
    }

    public int postJSONString(String body, Map headers) throws IOException {
        return postJSONString(body, headers, false);
    }

    public int postJSONString(String body, Map headers, boolean useWebViewCookieStore) throws IOException {
        if (headers == null) {
            headers = new HashMap();
        }

        HttpURLConnection conn = this.openConnection();
        conn.setDoOutput(true);
        conn.setFixedLengthStreamingMode(body.length());
        conn.setRequestMethod("POST");
        conn.setRequestProperty("Content-Type", "application/json");

        applyWebViewCookiesIfNeeded(conn, mUrl, headers, useWebViewCookieStore);

        Iterator<Map.Entry<String, String>> it = headers.entrySet().iterator();
        while (it.hasNext()) {
            Map.Entry<String, String> pair = it.next();
            conn.setRequestProperty(pair.getKey(), pair.getValue());
        }

        OutputStreamWriter os = null;
        try {
            os = new OutputStreamWriter(conn.getOutputStream());
            os.write(body);

        } finally {
            if (os != null) {
                os.flush();
                os.close();
            }
        }

        int responseCode = conn.getResponseCode();
        persistResponseCookiesIfNeeded(conn, mUrl, useWebViewCookieStore);
        return responseCode;
    }

    public int postJSONFile(File file, Map headers, UploadingProgressListener listener) throws IOException {
        return postJSONFile(new FileInputStream(file), headers, listener);
    }

    public int postJSONFile(File file, Map headers, UploadingProgressListener listener, boolean useWebViewCookieStore) throws IOException {
        return postJSONFile(new FileInputStream(file), headers, listener, useWebViewCookieStore);
    }

    public int postJSONFile(InputStream stream, Map headers, UploadingProgressListener listener) throws IOException {
        return postJSONFile(stream, headers, listener, false);
    }

    public int postJSONFile(InputStream stream, Map headers, UploadingProgressListener listener, boolean useWebViewCookieStore) throws IOException {
        if (headers == null) {
            headers = new HashMap();
        }

        final long streamSize = stream.available();
        HttpURLConnection conn = this.openConnection();

        conn.setDoInput(false);
        conn.setDoOutput(true);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            conn.setFixedLengthStreamingMode(streamSize);
        } else {
            conn.setChunkedStreamingMode(0);
        }
        conn.setRequestMethod("POST");
        conn.setRequestProperty("Content-Type", "application/json");

        applyWebViewCookiesIfNeeded(conn, mUrl, headers, useWebViewCookieStore);

        Iterator<Map.Entry<String, String>> it = headers.entrySet().iterator();
        while (it.hasNext()) {
            Map.Entry<String, String> pair = it.next();
            conn.setRequestProperty(pair.getKey(), pair.getValue());
        }

        long progress = 0;
        int bytesRead = -1;
        byte[] buffer = new byte[BUFFER_SIZE];

        BufferedInputStream is = null;
        BufferedOutputStream os = null;
        try {
            is = new BufferedInputStream(stream);
            os = new BufferedOutputStream(conn.getOutputStream());
            while ((bytesRead = is.read(buffer)) != -1) {
                os.write(buffer, 0, bytesRead);
                os.flush();
                progress += bytesRead;
                int percentage = (int) ((progress * 100L) / streamSize);
                if (listener != null) {
                    listener.onProgress(percentage);
                }
            }
        } finally {
            if (os != null) {
                os.flush();
                os.close();
            }
            if (is != null) {
                is.close();
            }
        }

        int responseCode = conn.getResponseCode();
        persistResponseCookiesIfNeeded(conn, mUrl, useWebViewCookieStore);
        return responseCode;
    }

    public static int postJSON(String url, JSONObject json, Map headers) throws IOException {
        return postJSON(url, json, headers, false);
    }

    public static int postJSON(String url, JSONArray json, Map headers) throws IOException {
        return postJSON(url, json, headers, false);
    }

    public static int postJSONFile(String url, File file, Map headers, UploadingProgressListener listener) throws IOException {
        return postJSONFile(url, file, headers, listener, false);
    }

    public static int postJSON(String url, JSONObject json, Map headers, boolean useWebViewCookieStore) throws IOException {
        HttpPostService service = new HttpPostService(url);
        String jsonString = "null";
        if (json != null) {
            jsonString = json.toString();
        }
        return service.postJSONString(jsonString, headers, useWebViewCookieStore);
    }

    public static int postJSON(String url, JSONArray json, Map headers, boolean useWebViewCookieStore) throws IOException {
        HttpPostService service = new HttpPostService(url);
        String jsonString = "null";
        if (json != null) {
            jsonString = json.toString();
        }
        return service.postJSONString(jsonString, headers, useWebViewCookieStore);
    }

    public static int postJSONFile(String url, File file, Map headers, UploadingProgressListener listener, boolean useWebViewCookieStore) throws IOException {
        HttpPostService service = new HttpPostService(url);
        return service.postJSONFile(file, headers, listener, useWebViewCookieStore);
    }
}
